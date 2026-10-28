#!/bin/sh
cd ..
echo Makking the main haxelib and setuping folder in same time..
mkdir ~/haxelib && haxelib setup ~/haxelib
echo Installing dependencies...
echo This might take a few moments depending on your internet speed.
haxelib install flixel 6.2.0
haxelib install flixel-addons 4.0.2
haxelib install flixel-tools 1.5.1
haxelib install hscript-iris 1.1.3
haxelib install tjson 1.4.0
haxelib install hxdiscord_rpc 1.3.0
haxelib install hxvlc 2.3.1 --skip-dependencies
haxelib install lime 8.3.2
haxelib install openfl 9.5.2
haxelib git flxanimate https://github.com/Dot-Stuff/flxanimate 768740a56b26aa0c072720e0d1236b94afe68e3e
haxelib git linc_luajit https://github.com/superpowers04/linc_luajit 1906c4a96f6bb6df66562b3f24c62f4c5bba14a7
haxelib git funkin.vis https://github.com/FunkinCrew/funkVis 02bada154b474c2554709b9d12aef0cbf0da3ec9
haxelib git grig.audio https://github.com/FunkinCrew/grig.audio 6409f3c6d1b4c52176813d3ede86c0d34e8af2c1
echo Finished!
