import hant.Log;
import haxe.io.Path;
import haxe.Json;
import stdlib.Std;
import sys.FileSystem;
import sys.io.File;
using StringTools;
using Lambda;
using Tools;

class Processor
{
	var root : YuiDoc;
	var destDir : String;
	var removePathPrefix : String;
	var typeMap : Map<String,String>;
	var itemDeclarationPrefx : String;
	var ignoreFiles : Array<String>;
	var ignoreClasses : Array<String>;
	var ignoreItems : Array<String>;
	var noDescriptions : Bool;
	var nativePackage : String;
	var generateDeprecated : Bool;
	var specifyTypes : Map<String,String>;
	var bracket : String;
	var space : String;
	var sortItems : Bool;
	var constructorFirst : Bool;
	var applyNativePackage : Bool;

	public function new
	(
		  srcJsonFilePath : String
		, destDir : String
		, removePathPrefix : String
		, typeMap : Array<String>
		, publicPrefix : Bool
		, ignoreFiles : Array<String>
		, ignoreClasses : Array<String>
		, ignoreItems : Array<String>
		, noDescriptions : Bool
		, nativePackage : String
		, applyNativePackage : Bool
		, generateDeprecated : Bool
		, specifyTypes : Array<String>
		, noNewLineOnBracket : Bool
		, lessSpaces : Bool
		, sortItems : Bool
		, constructorFirst : Bool
	)
	{
		this.root = Json.parse(File.getContent(srcJsonFilePath));
		this.destDir = Path.addTrailingSlash(destDir.replace("\\", "/"));
		this.removePathPrefix = Path.addTrailingSlash(removePathPrefix.replace("\\", "/"));
		this.typeMap = new Map<String,String>(); for (s in typeMap) this.typeMap.set(s.split("-")[0], s.split("-")[1]);
		this.itemDeclarationPrefx = publicPrefix ? "public " : "";
		this.ignoreFiles = ignoreFiles.map(function(p) return p.replace("\\", "/"));
		this.ignoreClasses = ignoreClasses;
		this.ignoreItems = ignoreItems;
		this.noDescriptions = noDescriptions;
		this.nativePackage = nativePackage;
		this.applyNativePackage = applyNativePackage;
		this.generateDeprecated = generateDeprecated;
		this.specifyTypes = new Map<String,String>(); for (s in specifyTypes) this.specifyTypes.set(s.split("-")[0], s.split("-")[1]);
		this.bracket = noNewLineOnBracket ? " {\n" : "\n{";
		this.space = lessSpaces ? "" : " ";
		this.sortItems = sortItems;
		this.constructorFirst = constructorFirst;
	}
	
	public function run()
	{
		applySpecifyTypes();
		
		for (className in Reflect.fields(root.classes))
		{
			Log.start("Process class " + className);
			
			var klass : Klass = Reflect.field(root.classes, className);
			
			if (isIgnore(ignoreClasses, klass.module, className) || (!generateDeprecated && klass.deprecated))
			{
				Log.finishSuccess("SKIP");
				continue;
			}
			
			var file = Std.string(klass.file).replace("\\", "/");
			if (file.startsWith(removePathPrefix)) file = file.substr(removePathPrefix.length);
			if (ignoreFiles.has(file))
			{
				Log.finishSuccess("SKIP");
				continue;
			}
			file = Path.withoutExtension(file) + ".hx";
			file = destDir + file;
			
			var items = getKlassItems(klass);
			items.properties = uniqueItems(items.properties);
			items.methods = uniqueItems(items.methods);
			
			var eventsDeclarationCode = items.events.filter(function(item) return item.params != null).map(function(item)
			{
				var eventClassName = item.getClass() + capitalize(item.name) + "Event";
				
				return "typedef " + eventClassName + " =" + bracket + "\n" + item.params.map(function(p)
				{
					return "\tvar " + p.name + space + ":" + space + getHaxeType(item.module, p.type) + ";";
				}
				).join("\n") + "\n}\n";
			}
			).join("\n");
			
			var propertiesCode = items.properties.map(function(item) return getPropertyCode(items.properties.concat(items.methods), item)).join("\n");
			
			if (sortItems) items.methods.sort(function(a, b) return a.name<b.name ? -1 : (a.name>b.name ? 1 : 0));
			var methodsCode = items.methods.map(function(item) return getMethodCode(items.properties.concat(items.methods), item)).join("\n");
			
			var eventsCode = items.events.filter(function(item) return !isEventOverride(item)).map(function(item)
			{
				var eventClassName = item.getClass() + capitalize(item.name) + "Event";
				
				if (item.params == null)
				{
					var reLinkToEvent = ~/See\s+the\s+[{][{]#crossLink\s+"([_a-z][_a-z0-9]*)"[}][}][{][{]\/crossLink[}][}]\s+class\s+for\s+a\s+listing\s+of\s+event\s+properties/i;
					if (reLinkToEvent.match(item.description))
					{
						eventClassName = reLinkToEvent.matched(1);
					}
					else
					{
						eventClassName = "Dynamic";
						Log.echo("Warning: unknow params for event '" + item.name + "' (" + item.file + " : " + item.line + ").");
					}
				}
				
				return getDescriptionCode(item) + "\t" + itemDeclarationPrefx + (item.isStatic() ? "static " : "") + "inline function add"    + capitalize(item.name) + "EventListener(handler:" + eventClassName + "->Void, ?useCapture:Bool) : Dynamic return addEventListener(\""    + item.name + "\", handler, useCapture);\n"
												+ "\t" + itemDeclarationPrefx + (item.isStatic() ? "static " : "") + "inline function remove" + capitalize(item.name) + "EventListener(handler:" + eventClassName + "->Void, ?useCapture:Bool) : Void"   + " removeEventListener(\"" + item.name + "\", handler, useCapture);";
			}
			).join("\n");
			
			var result = [];
			if (!applyNativePackage && klass.module != "")
			{
				result.push("package " + klass.module.toLowerCase() + ";");
				result.push("");
			}
			else
			if (applyNativePackage && nativePackage != "")
			{
				result.push("package " + nativePackage + ";");
				result.push("");
			}
			
			if (eventsDeclarationCode != "") result.push(eventsDeclarationCode);
			
			var klassDescriptionCode = getDescriptionCode(klass, "").rtrim();
			if (klassDescriptionCode != "") result.push(klassDescriptionCode);
			
			if (!applyNativePackage) result.push("@:native(\"" + (nativePackage != "" ? nativePackage + "." : "") + klass.name + "\")");
			result.push("extern class " + klass.name + (klass.getExtends() != null && klass.getExtends() != "" ? " extends " + getHaxeType(klass.module, klass.getExtends()) : "") + bracket);
			
			var innerClassCode = "";
			if (constructorFirst)
			{
				if (klass.is_constructor == 1)	innerClassCode += getConstructorCode(items.properties.concat(items.methods), klass);
			}
			if (propertiesCode != "")			innerClassCode += propertiesCode + "\n\n";
			if (!constructorFirst)
			{
				if (klass.is_constructor == 1)	innerClassCode += getConstructorCode(items.properties.concat(items.methods), klass);
			}
			if (methodsCode != "")				innerClassCode += methodsCode + "\n\n";
			if (eventsCode != "")				innerClassCode += eventsCode + "\n\n";
			result.push(innerClassCode.rtrim());
			
			result.push("}");
			
			var destFileDir = Path.join([ destDir, !applyNativePackage ? klass.module.toLowerCase() : nativePackage ]);
			FileSystem.createDirectory(destFileDir);
			File.saveContent(Path.join([ destFileDir, klass.name + ".hx"]), result.join("\n").replace("\n", "\r\n"));
			
			Log.finishSuccess();
		}
	}
	
	function applySpecifyTypes()
	{
		for (key in specifyTypes.keys())
		{
			var parts = key.split(".");
			if (parts.length < 2 || parts.length > 3) throw "Apply specified types: invalid value '" + parts + "' for --specify-type option.";
			var klass : Klass = Reflect.field(root.classes, parts[0]);
			if (klass == null) throw "Apply specified types: class '" + parts[0] + "' is not found. Check your --specify-type option.";
			var item = getKlassItem(klass, parts[1], false);
			if (item == null) item = getKlassItem(klass, parts[1], true);
			if (item != null)
			{
				if (parts.length == 2)
				{
					if (item.itemtype == "method")
					{
						var ret = item.getReturn();
						if (ret == null) { ret = { description:null, type:null }; item.setReturn(ret); }
						ret.type = specifyTypes.get(key);
					}
					else
					{
						item.type = specifyTypes.get(key);
					}
				}
				else
				{
					var found = false;
					for (param in item.params)
					{
						if (param.name == parts[2])
						{
							found = true;
							param.type = specifyTypes.get(key);
							break;
						}
					}
					if (!found) throw "Apply specified types: can't found '" + key + "' for --specify-type option.";
				}
			}
			else
			{
				throw "Apply specified types: can't found class item '" + parts[0] + "." + parts[1] + "'. Check your command-line option '--specify-type'.";
			}
		}
	}
	
	function getKlassItems(klass:Klass) : { properties:Array<Item>, methods:Array<Item>, events:Array<Item> }
	{
		var properties = new Array<Item>();
		var methods = new Array<Item>();
		var events = new Array<Item>();
		
		for (i in 0...root.classitems.length)
		{
			var item = root.classitems[i];
			
			var file = Std.string(item.file).replace("\\", "/");
			if (file.startsWith(removePathPrefix)) file = file.substr(removePathPrefix.length);
			if (ignoreFiles.has(file)) continue;
			
			if (item.access == "private") continue;
			if (item.access == "protected") continue;
			
			if (item.module == klass.module && item.getClass() == klass.name)
			{
				if (!generateDeprecated && item.deprecated) continue;
				
				var reProperty = new EReg("^property\\s+([_a-z][_a-z0-9]*)\\s*$", "i");
				
				if (reProperty.match(Std.string(item.description)))
				{
					if (item.itemtype == null) item.itemtype = "property";
					if (item.name == null) item.name = reProperty.matched(1);
				}
				
				if (item.name == null)
				{
					if (Std.string(item.description).indexOf("Docced in superclass") >= 0) continue;
					var nativeLine = getSourceLine(item);
					if (nativeLine.indexOf("@ignore") >= 0) continue;
					if (nativeLine.indexOf("docced in super class") >= 0) continue;
				}
				
				if (item.name == null)
				{
					if (item.description != null && (item.description.indexOf("#property") >= 0 || item.description.indexOf("#method") >= 0)) continue;
					
					Log.echo("Warning: unknow item name, so useful var/method may be ignored (" + item.file + " : " + item.line + ").");
					continue;
				}
				
				if (isIgnore(ignoreItems, item.getClass(), item.name)) continue;
				
				fillItemFieldsFromSuperClass(item);
				
				if (item.itemtype == null)
				{
					if (item.getReturn() != null)
					{
						item.itemtype = "method";
					}
				}
				
				if (item.itemtype == "method" && (item.params == null || item.getReturn() == null))
				{
					var nativeLine = getSourceLine(item, true);
					
					var reChain = ~/\s*([_a-z][_a-z0-9]*[.]+)([_a-z][_a-z0-9]*)\s*[=]\s*([_a-z][_a-z0-9]*[.]+)([_a-z][_a-z0-9]*)\s*;/i;
					if (reChain.match(nativeLine) && reChain.matched(1) == reChain.matched(3) && reChain.matched(2) == item.name)
					{
						var prevItem = getKlassItem(klass, reChain.matched(4), item.isStatic());
						if (prevItem != null)
						{
							if (item.params == null) item.params = prevItem.params;
							if (item.getReturn() == null) item.setReturn(prevItem.getReturn());
						}
					}
				}
				
				if (item.itemtype == "method" && !item.isStatic())
				{
					var superClass = getMostSuperClassWithItem(klass, item.name);
					var superItem = getKlassItem(superClass, item.name, false);
					
					var childClasses = getChildClasses(superClass.name);
					for (childClass in childClasses)
					{
						var childItem = getKlassItem(childClass, item.name, false);
						if (childItem != null)
						{
							if ((superItem.params != null ? superItem.params.length : 0) < (childItem.params != null ? childItem.params.length : 0))
							{
								if (superItem.params == null) superItem.params = [];
								for (i in superItem.params.length...childItem.params.length)
								{
									var p = childItem.params[i];
									if (!p.isOptional()) p.setOptional(true);
									superItem.params.push(p);
								}
							}
							
							// sync params names and types
							if (childItem.params != null)
							{
								for (i in 0...childItem.params.length)
								{
									var p0 = superItem.params[i];
									var p1 = childItem.params[i];
									
									if (p0.type != p1.type)
									{
										p0.type = "Dynamic";
										p1.type = "Dynamic";
									}
									
									if (p0.isOptional() || p1.isOptional())
									{
										p0.setOptional(true);
										p1.setOptional(true);
									}
								}
							}
						}
					}
				}
				
				switch (item.itemtype)
				{
					case "property":
						properties.push(item);
					
					case "method":
						methods.push(item);
						
					case "event":
						events.push(item);
					
					case _:
						throw "Unknow itemtype for item = " + item;
				}
			}
		}
		
		if (klass.uses != null)
		{
			for (mixKlassName in klass.uses)
			{
				var mixKlass : Klass = Reflect.field(root.classes, mixKlassName);
				if (mixKlass != null)
				{
					var mixMethods = getKlassItems(mixKlass).methods;
					for (mixMethod in mixMethods)
					{
						if (!methods.exists(function(m) return m.name == mixMethod.name))
						{
							methods.push(mixMethod);
						}
					}
				}
			}
		}
		
		return { properties:properties, methods:methods, events:events };
	}
	
	function getSourceLine(item:Item, afterComment=false) : String
	{
		if (FileSystem.exists(item.file))
		{
			var text = File.getContent(item.file).replace("\r", "");
			
			if (!afterComment)
			{
				return text.split("\n")[item.line - 1];
			}
			else
			{
				var n = text.split("\n").slice(0, item.line - 1).fold((function(s, n) return n + s.length + 1), 1);
				text = text.substr(n).ltrim();
				if (text.startsWith("/*"))
				{
					n = text.indexOf("*/");
					text = text.substr(n + 2).ltrim();
				}
				return text.split("\n")[0];
			}
		}
		return "";
	}
	
	function fillItemFieldsFromSuperClass(item:Item)
	{
		var klass : Klass = Reflect.field(root.classes, item.getClass());
		var superKlassName = klass.getExtends();
		while (superKlassName != null && superKlassName != "")
		{
			var superKlass : Klass = Reflect.field(root.classes, superKlassName);
			
			if (superKlass == null)
			{
				if (![ "Array" ].has(superKlassName))
				{
					Log.echo("Warning: class '" + superKlassName + "' is not found.");
				}
				return;
			}
			
			var superItem = getKlassItem(superKlass, item.name, item.isStatic());
			if (superItem != null)
			{
				if (item.getReturn() == null)
				{
					item.setReturn(superItem.getReturn());
				}
				else
				if (item.getReturn().type != superItem.getReturn().type)
				{
					item.getReturn().type = superItem.getReturn().type;
				}
				
				if (item.params == null)
				{
					item.params = superItem.params;
				}
			}
			
			superKlassName = superKlass.getExtends();
		}
	}
	
	function getKlassItem(klass:Klass, itemName:String, isStatic:Bool) : Item
	{
		for (item in root.classitems)
		{
			if (!Reflect.hasField(item, "module"))
			{
				throw "Unknow module for item = " + item;
			}
			
			if (!Reflect.hasField(klass, "module"))
			{
				throw "Unknow module for class = " + klass;
			}
			
			if (item.module == klass.module && item.getClass() == klass.name && item.name == itemName && item.isStatic() == isStatic)
			{		
				return item;
			}
		}
		return null;
	}
	
	function getHaxeType(curModule:String, type:String) : String
	{
		type = type.replace(" ", "");
		if (type.startsWith("{") && type.endsWith("}")) type = type.substr(1, type.length - 2);
		
		if (typeMap.exists(type)) return typeMap.get(type);
		
		if (type.indexOf("|") >= 0) return "Dynamic";
		
		type = getFullKlassName(curModule, type);
		
		var ltype = type.toLowerCase();
		
		if (ltype == "string") return "String";
		if (ltype == "boolean") return "Bool";
		if (ltype == "number") return "Float";
		if (ltype == "object") return "Dynamic";
		if (ltype == "function") return "Dynamic";
		if (ltype == "array") return "Array<Dynamic>";
		if (ltype == "*") return "Dynamic";
		
		var reTypedArray = ~/^array\[(.*)\]$/;
		if (reTypedArray.match(ltype))
		{
			return "Array<" + getHaxeType(curModule, reTypedArray.matched(1)) + ">";
		}
		
		return type;
	}
	
	function getParamsCode(item:Item)
	{
		if (item.params != null)
		{
			var ss = item.params.map(function(p)
			{
				if (p.type == null)
				{
					Log.echo("Warning: method's param type not specified (" + item.module+"." + item.name+"." + p.name+").");
				}
				return (p.isOptional() ? "?" : "")
					+ fixKeyword(p.name) + ":" 
					+ (p.type != null ? getHaxeType(item.module, p.type) : "Dynamic");
			});
			return "(" + ss.join(", ") + ")";
		}
		return "()";
	}
	
	function getDescriptionCode(item:{ description:String }, prefix="\t")
	{
		if (item.description == null || item.description == "") return "";
		return prefix + "/**\n" + item.description.split("\n").map(function(s) return prefix + " * " + s).join("\n") + "\n" + prefix + " */\n";
	}
	
	function capitalize(s:String)
	{
		if (s == "") return "";
		return s.substr(0, 1).toUpperCase() + s.substr(1);
	}
	
	function isIgnore(ignores:Array<String>, prefix:String, name:String)
	{
		return ignores.exists(function(s)
		{
			if (s.indexOf("*") < 0)
			{
				var n = s.lastIndexOf(".");
				return n >= 0 ? s.substr(0, n) == prefix && s.substr(n + 1) == name : s == name;
			}
			else
			{
				var re = new EReg(s.replace(".", "\\.").replace("*", ".+"), "");
				return re.match((prefix != null && prefix != "" ? prefix + "." : "") + name);
			}
		});
	}
	
	function getConstructorCode(items:Array<Item>, klass:Klass) : String
	{
		return getMethodCode(items, cast { name:"new", "return":{ type:"Void" }, params:klass.params }) + "\n\n";
	}
	
	function getPropertyCode(items:Array<Item>, item:Item)
	{
		if (item.type == null)
		{
			throw "Unknow type for property = " + item;
		}
		
		var haxeType = getHaxeType(item.module, item.type);
		
		if (item.isStatic() || !items.exists(function(i) return i.name == item.name && i.isStatic()))
		{
			return getDescriptionCode(item) 
				+ "\t" 
				+ itemDeclarationPrefx 
				+ (item.isStatic() ? "static " : "") 
				+ "var " + item.name + space + ":" + space + haxeType + ";";
		}
		else
		{
			
			
			return getDescriptionCode(item) 
				+ "\t" 
				+ itemDeclarationPrefx 
				+ "var " + item.name + "_(get, set)" + space + ":" + space + haxeType + ";\n"
				+ "\tinline function get_" + item.name + "_()" + space + ":" + space + haxeType + " return Reflect.field(this, \"" + item.name + "\");\n"
				+ "\tinline function set_" + item.name + "_(v:" + haxeType + ")" + space + ":" + space + haxeType + " { Reflect.setField(this, \"" + item.name + "\", v); return v; }";
		}
	}
	
	function getMethodCode(items:Array<Item>, item:Item)
	{
		var ret = item.getReturn();
		if (ret == null)
		{
			Log.echo("Warning: unknow return for method '" + item.name + "'.");
		}
		if (ret != null && ret.type == null)
		{
			throw "Unknow return type for method = " + item;
		}
		try
		{
			
			var retHaxeType = ret != null ? getHaxeType(item.module, ret.type) : "Void";
			
			if (item.isStatic() || !items.exists(function(i) return i.name == item.name && i.isStatic()))
			{
				return getDescriptionCode(item) 
					+ "\t" 
					+ (isMethodOverride(item) ? "override " : "") 
					+ itemDeclarationPrefx 
					+ (item.isStatic() ? "static " : "") 
					+ "function " + item.name + getParamsCode(item) + space + ":" + space + retHaxeType + ";";
			}
			else
			{
				return getDescriptionCode(item) 
					+ "\t" 
					+ itemDeclarationPrefx 
					+ "inline "
					+ "function " + item.name + "_" + getParamsCode(item) + space + ":" + space + retHaxeType
					+ (retHaxeType != "Void" ? " return" : "")
					+ " Reflect.callMethod(this, \"" + item.name + "\", [ " + (item.params != null ? item.params.map(function(p) return p.name).join(", ") : "") + " ]);";
			}
		}
		catch (e:Dynamic)
		{
			throw "Unknow param type for method = " + item;
		}
	}
	
	function isEventOverride(item:Item) : Bool
	{
		var klass : Klass = Reflect.field(root.classes, item.getClass());
		var superKlassName = klass.getExtends();
		while (superKlassName != null && superKlassName != "")
		{
			var superKlass : Klass = Reflect.field(root.classes, superKlassName);
			
			if (superKlass == null) return false;
			
			var superItem = getKlassItem(superKlass, item.name, item.isStatic());
			if (superItem != null && superItem.itemtype == "event") return true;
			
			superKlassName = superKlass.getExtends();
		}
		return false;
	}
	
	function isMethodOverride(item:Item) : Bool
	{
		if (item.name == "new" || item.isStatic()) return false;
		
		var klass : Klass = Reflect.field(root.classes, item.getClass());
		var superKlassName = klass.getExtends();
		while (superKlassName != null && superKlassName != "")
		{
			var superKlass : Klass = Reflect.field(root.classes, superKlassName);
			
			if (superKlass == null) return false;
			
			var superItem = getKlassItem(superKlass, item.name, item.isStatic());
			if (superItem != null && superItem.itemtype != "event") return true;
			
			superKlassName = superKlass.getExtends();
		}
		return false;
	}
	
	function getFullKlassName(curModule:String, klassName:String) : String
	{
		var klass : Klass = Reflect.field(root.classes, klassName);
		if (klass == null) return klassName;
		
		var pack = "";
		if (!applyNativePackage)
		{
			if (klass.module != curModule && klass.module != null) pack = klass.module.toLowerCase();
		}
		
		return (pack != "" ? pack + "." : "") + klassName;
	}
	
	function getChildClasses(klassName:String) : Array<Klass>
	{
		var r = [];
		
		for (className in Reflect.fields(root.classes))
		{
			var klass : Klass = Reflect.field(root.classes, className);
			if (isParentOf(klassName, klass))
			{
				r.push(klass);
			}
		}
		
		return r;
	}
	
	function getMostSuperClassWithItem(klass:Klass, itemName:String) : Klass
	{
		var r = klass;
		while (klass.getExtends() != null)
		{
			klass = Reflect.field(root.classes, klass.getExtends());
			if (getKlassItem(klass, itemName, false) != null) r = klass;
		}
		return r;
		
	}
	
	function isParentOf(parentKlassName:String, klass:Klass) : Bool
	{
		while (klass.getExtends() != null)
		{
			if (klass.getExtends() == parentKlassName) return true;
			klass = Reflect.field(root.classes, klass.getExtends());
		}
		return false;
	}
	
	function fixKeyword(s:String) : String
	{
		var keywords = [ "override" ];
		return keywords.indexOf(s) < 0 ? s : s + "_";
	}
	
	
	function uniqueItems(items:Array<Item>) : Array<Item>
	{
		var i = items.length - 1; while (i > 0)
		{
			var prevItems = items.slice(0, i);
			if (prevItems.exists(function(item) return items[i].name == item.name))
			{
				Log.echo("Warning item '" + items[i].name + "' defined several times. Used last define.");
				var len = items.length;
				items = prevItems.filter(function(item) return items[i].name != item.name).concat(items.slice(i));
				i -= len - items.length;
			}
			i--;
		}
		return items;
	}
}