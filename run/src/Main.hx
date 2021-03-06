import hant.CmdOptions;
import hant.Log;
import neko.Lib;

class Main
{
	static function main()
	{
		var args = Sys.args();
		if (args.length > 0)
		{
			Sys.setCwd(args.pop());
		}
		else
		{
			Lib.println("run this program via haxelib utility.");
			Sys.exit(1);
		}
		
		Log.instance = new Log();
		
		var parser = new CmdOptions();
		parser.add("destDir", "library", null, "Output directory.");
		parser.add("srcJsonFilePath", "out/data.json", [ "-src", "--source" ], "Source yuidoc json file path. Default is 'out/data.json'.");
		parser.add("removePathPrefix", "", [ "-pprefix", "--remove-path-prefix" ], "Source files path prefix to remove. Specify here base source directory (same as for yuidoc).");
		parser.addRepeatable("typeMap", String, [ "-tm", "--type-map" ], "Map basic types in form 'from-to'. For example: Boolean-Bool");
		parser.add("publicPrefix", false, [ "--public-prefix" ], "Write 'public' before class member declarations.");
		parser.addRepeatable("ignoreFiles", String, [ "-ifile", "--ignore-file" ], "Path to source file to ignore.");
		parser.addRepeatable("ignoreClasses", String, [ "-iclass", "--ignore-class" ], "Class name to ignore. Masks with '*' is supported.");
		parser.addRepeatable("ignoreItems", String, [ "-iitem", "--ignore-items" ], "Class member to ignore. Masks with '*' is supported.");
		parser.add("noDescriptions", false, [ "-nd", "--no-descriptions" ], "Do not generate descriptions.");
		parser.add("nativePackage", "", [ "-np", "--native-package" ], "Native package for @:native meta.");
		parser.add("applyNativePackage", false, [ "-anp", "--apply-native-package" ], "Use native package specified by '-np' as haxe package and don't generate @:native meta.");
		parser.add("generateDeprecated", false, [ "--generate-deprecated" ], "Generate deprecated classes/members.");
		parser.addRepeatable("specifyTypes", String, [ "-st", "--specify-type" ], "Specify method argument or return type. Example: DisplayObject.hitTest.x-Float");
		parser.add("noNewLineOnBracket", false, [ "--no-new-line-on-bracket" ], "Output code style. Generate '{' on the same line.");
		parser.add("lessSpaces", false, [ "--less-spaces" ], "Output code style. Generate less spaces.");
		parser.add("sortItems", false, [ "--sort-items" ], "Output code style. Sort items alphabetically.");
		parser.add("constructorFirst", false, [ "--constructor-first" ], "Output code style. Place constructor first.");
		
		if (args.length > 0)
		{
			var options = parser.parse(args);
			var processor = new Processor
			(
				  options.get("srcJsonFilePath")
				, options.get("destDir")
				, options.get("removePathPrefix")
				, options.get("typeMap")
				, options.get("publicPrefix")
				, options.get("ignoreFiles")
				, options.get("ignoreClasses")
				, options.get("ignoreItems")
				, options.get("noDescriptions")
				, options.get("nativePackage")
				, options.get("applyNativePackage")
				, options.get("generateDeprecated")
				, options.get("specifyTypes")
				, options.get("noNewLineOnBracket")
				, options.get("lessSpaces")
				, options.get("sortItems")
				, options.get("constructorFirst")
			);
			processor.run();
		}
		else
		{
			Lib.println("yuidoc2haxe - generated haxe externs from the yuidoc's json.");
			Lib.println("Usage: yuidoc2haxe [<options>] <destDir>");
			Lib.println("  Where options:");
			Lib.println(parser.getHelpMessage("    "));
		}
	}
}
