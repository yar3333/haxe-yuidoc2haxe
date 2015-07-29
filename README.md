# yuidoc2haxe #

Haxe externs generating tool. Use [yuidoc](http://yui.github.io/yuidoc/) output as source. At this moment this tool used to convert [createjs](http://createjs.com) javascript libraries to haxe externs.

## Usage ##
haxelib run yuidoc2haxe [<options>] <destDir>

### Options ###
```text
-src, --source                 Source yuidoc json file path. Default is 'out/data.json'.
-pprefix, --remove-path-prefix Source files path prefix to remove. Specify here base source directory (same as for yuidoc).
-tm, --type-map                Map basic types in form 'from-to'. For example: Boolean-Bool
--public-prefix                Write 'public' before class member declarations.
-ifile, --ignore-file          Path to source file to ignore.
-iclass, --ignore-class        Class name to ignore. Masks with '*' is supported.
-iitem, --ignore-items         Class member to ignore. Masks with '*' is supported.
-nd, --no-descriptions         Do not generate descriptions.
-np, --native-package          Native package for @:native meta.
-anp, --apply-native-package   Use native package specified by '-np' as haxe package and don't generate @:native meta.
--generate-deprecated          Generate deprecated classes/members.
-st, --specify-type            Specify method argument or return type. Example: DisplayObject.hitTest.x-Float
--no-new-line-on-bracket       Output code style. Generate '{' on the same line.
--less-spaces                  Output code style. Generate less spaces.
--sort-items                   Output code style. Sort items alphabetically.
--constructor-first            Output code style. Place constructor first.
```

## Example ##
```shell
#generate json by javascript sources
yuidoc -p -o out easeljs/src

#generate haxe externs by json
haxelib run yuidoc2haxe -src out/data.json --remove-path-prefix easeljs/src --native-package createjs --apply-native-package library
```