package backend;

import flixel.graphics.FlxGraphic;
import flixel.graphics.tile.FlxDrawBaseItem;
import flixel.graphics.tile.FlxDrawQuadsItem;
import openfl.Lib;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.PixelSnapping;
import openfl.display3D.Context3DMipFilter;
import openfl.display3D.textures.TextureBase;
import openfl.geom.Matrix;
import shaders.RGBPalette.RGBPaletteShader;

@:access(openfl.display.BitmapData)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.textures.TextureBase)
class AntiAliasing
{
	public static inline var CLASSIC:String = 'Classic';
	public static inline var HIGH:String = 'High';
	public static inline var MAX:String = 'Max';
	public static inline var ULTRA:String = 'Ultra';
	public static final LEVELS:Array<String> = [ULTRA, MAX, HIGH, CLASSIC];

	static inline var GL_MULTISAMPLE:Int = 0x809D;
	static inline var GL_TEXTURE_LOD_BIAS:Int = 0x8501;

	public static var msaaSamples(default, null):Int = 0;
	public static var mipmapsSupported(default, null):Bool = false;
	public static var msaaActive(default, null):Bool = false;
	public static var mipmapsActive(default, null):Bool = false;
	public static var supersamplingActive(default, null):Bool = false;
	public static var mipmapBias(default, set):Float = -0.5;
	public static var renderer(default, null):String = '?';
	public static var glVersion(default, null):String = '?';
	public static var mipmapBuilds(default, null):Int = 0;

	static var desktopGL:Bool = false;
	static var ready:Bool = false;
	static var entries:Map<FlxGraphic, MipmapEntry> = new Map();
	static var bigFrame:BitmapData;
	static var bigView:Bitmap;
	static var bigMatrix:Matrix = new Matrix();

	static function init():Bool
	{
		if (ready) return true;
		var stage = Lib.current.stage;
		if (stage == null || stage.context3D == null) return false;
		ready = true;
		try
		{
			var gl = stage.context3D.gl;
			glVersion = Std.string(gl.getParameter(gl.VERSION));
			renderer = Std.string(gl.getParameter(gl.RENDERER));
			var samples:Dynamic = gl.getParameter(gl.SAMPLES);
			msaaSamples = (samples != null) ? Std.int(samples) : 0;
			desktopGL = !StringTools.startsWith(glVersion, 'OpenGL ES');
			var major:Null<Int> = Std.parseInt(desktopGL ? glVersion : glVersion.substr('OpenGL ES '.length));
			if (major == null) major = 0;
			mipmapsSupported = desktopGL ? major >= 2 : (major >= 3 || hasExtension(gl, 'OES_texture_npot'));
			if (msaaSamples > 1)
			{
				if (desktopGL) gl.disable(GL_MULTISAMPLE);
				else msaaActive = true;
			}
		}
		catch (e:Dynamic)
		{
			trace('Anti-aliasing: could not read the GPU settings: $e');
		}
		FlxG.signals.postDraw.add(checkMipmaps);
		FlxG.signals.postDraw.addOnce(backend.pixel.VortexPixel.init);
		return true;
	}

	public static function apply():Void
	{
		var level:String = ClientPrefs.data.antialiasing ? ClientPrefs.data.antialiasingQuality : CLASSIC;
		setMSAA(level == HIGH || level == MAX || level == ULTRA);
		setMipmaps(level == MAX || level == ULTRA);
		setSupersampling(level == ULTRA);
	}

	public static function setSupersampling(on:Bool):Void
	{
		if (!init() || on == supersamplingActive) return;
		var game = FlxG.game;
		if (game == null || game.parent == null) return;
		supersamplingActive = on;
		if (on)
		{
			bigView = new Bitmap(null, PixelSnapping.NEVER, true);
			game.parent.addChildAt(bigView, game.parent.getChildIndex(game) + 1);
			FlxG.signals.postDraw.add(drawSupersampled);
		}
		else
		{
			FlxG.signals.postDraw.remove(drawSupersampled);
			game.visible = true;
			if (bigView != null && bigView.parent != null) bigView.parent.removeChild(bigView);
			bigView = null;
			if (bigFrame != null) bigFrame.dispose();
			bigFrame = null;
		}
	}

	static function drawSupersampled():Void
	{
		var stage = Lib.current.stage;
		var game = FlxG.game;
		var width:Int = stage.stageWidth * 2;
		var height:Int = stage.stageHeight * 2;
		try
		{
			if (bigFrame == null || bigFrame.width != width || bigFrame.height != height)
			{
				if (bigFrame != null) bigFrame.dispose();
				bigFrame = BitmapData.fromTexture(stage.context3D.createRectangleTexture(width, height, BGRA, true));
				bigView.bitmapData = bigFrame;
				bigView.smoothing = true;
				bigView.scaleX = bigView.scaleY = 0.5;
			}
			bigFrame.fillRect(bigFrame.rect, 0);
			bigMatrix.setTo(2 * game.scaleX, 0, 0, 2 * game.scaleY, 2 * game.x, 2 * game.y);
			bigFrame.draw(game, bigMatrix, null, null, null, true);
			game.visible = false;
		}
		catch (e:Dynamic)
		{
			trace('Anti-aliasing: supersampling turned off: $e');
			setSupersampling(false);
		}
	}

	static function set_mipmapBias(value:Float):Float
	{
		mipmapBias = value;
		if (ready && desktopGL)
			for (graphic => entry in entries)
				if (entry.ready && !graphic.isDestroyed) applyBias(entry.texture);
		return value;
	}

	static function applyBias(texture:TextureBase):Void
	{
		var context = Lib.current.stage.context3D;
		context.__bindGLTexture2D(texture.__textureID);
		context.gl.texParameterf(context.gl.TEXTURE_2D, GL_TEXTURE_LOD_BIAS, mipmapBias);
		context.__bindGLTexture2D(null);
	}

	public static function setMSAA(on:Bool):Void
	{
		if (!init() || msaaSamples < 2 || !desktopGL) return;
		var gl = Lib.current.stage.context3D.gl;
		if (on) gl.enable(GL_MULTISAMPLE);
		else gl.disable(GL_MULTISAMPLE);
		msaaActive = on;
	}

	public static function setMipmaps(on:Bool):Void
	{
		if (!init()) return;
		on = on && mipmapsSupported;
		if (on == mipmapsActive) return;
		mipmapsActive = on;
		for (graphic => entry in entries)
		{
			if (graphic.isDestroyed) continue;
			var want:Bool = on || enhanced(graphic);
			if (want && (!entry.ready || outdated(graphic, entry))) build(graphic, entry);
			graphic.shader.bitmap.mipFilter = (want && entry.ready) ? MIPLINEAR : MIPNONE;
		}
	}

	public static function track(graphic:FlxGraphic):Void
	{
		if (!init() || !mipmapsSupported || graphic == null || graphic.bitmap == null || entries.exists(graphic)) return;
		var entry = new MipmapEntry();
		entries.set(graphic, entry);
		if (mipmapsActive || enhanced(graphic))
		{
			build(graphic, entry);
			graphic.shader.bitmap.mipFilter = entry.ready ? MIPLINEAR : MIPNONE;
		}
	}

	public static function prepareDraw(item:FlxDrawBaseItem<Dynamic>, camera:FlxCamera):Void
	{
		var quads:FlxDrawQuadsItem = Std.downcast(item, FlxDrawQuadsItem);
		if (quads == null || quads.graphics == null) return;
		var graphic:FlxGraphic = quads.graphics;
		var shader = quads.shader != null ? quads.shader : graphic.shader;
		if (shader == null || shader.bitmap == null) return;
		if (shader != graphic.shader && !Std.isOfType(shader, RGBPaletteShader)) return;
		var entry:MipmapEntry = (mipmapsActive || enhanced(graphic)) ? entries.get(graphic) : null;
		var smooth:Bool = camera.antialiasing || quads.antialiasing;
		shader.bitmap.mipFilter = (entry != null && entry.ready && smooth) ? MIPLINEAR : MIPNONE;
	}

	static function checkMipmaps():Void
	{
		var gone:Array<FlxGraphic> = null;
		for (graphic => entry in entries)
		{
			var bitmap = graphic.bitmap;
			if (graphic.isDestroyed || bitmap == null || !bitmap.__isValid)
			{
				if (gone == null) gone = [];
				gone.push(graphic);
				continue;
			}
			if ((mipmapsActive || enhanced(graphic)) && outdated(graphic, entry))
			{
				build(graphic, entry);
				graphic.shader.bitmap.mipFilter = entry.ready ? MIPLINEAR : MIPNONE;
			}
		}
		if (gone != null) for (graphic in gone) entries.remove(graphic);
	}

	static function enhanced(graphic:FlxGraphic):Bool
		return graphic.bitmap != null && backend.pixel.VortexPixel.isEnhanced(graphic.bitmap.__texture);

	static function outdated(graphic:FlxGraphic, entry:MipmapEntry):Bool
	{
		var bitmap = graphic.bitmap;
		return entry.texture != bitmap.__texture || entry.version != bitmap.__textureVersion
			|| bitmap.__textureContext != Lib.current.stage.context3D.__context
			|| (bitmap.image != null && bitmap.image.version > bitmap.__textureVersion);
	}

	static function build(graphic:FlxGraphic, entry:MipmapEntry):Void
	{
		entry.ready = false;
		mipmapBuilds++;
		try
		{
			var context = Lib.current.stage.context3D;
			var bitmap = graphic.bitmap;
			var texture:TextureBase = bitmap.getTexture(context);
			if (texture == null) return;
			var gl = context.gl;
			if (backend.pixel.VortexPixel.isCompressed(texture))
			{
				var ok = backend.pixel.VortexPixel.ensureMips(texture);
				if (ok && desktopGL) applyBias(texture);
				entry.texture = texture;
				entry.version = bitmap.__textureVersion;
				entry.ready = ok;
				return;
			}
			var guard:Int = 0;
			while (gl.getError() != gl.NO_ERROR && guard++ < 16) {}
			context.__bindGLTexture2D(texture.__textureID);
			gl.generateMipmap(gl.TEXTURE_2D);
			if (desktopGL) gl.texParameterf(gl.TEXTURE_2D, GL_TEXTURE_LOD_BIAS, mipmapBias);
			var ok:Bool = gl.getError() == gl.NO_ERROR;
			context.__bindGLTexture2D(null);
			entry.texture = texture;
			entry.version = bitmap.__textureVersion;
			entry.ready = ok;
		}
		catch (e:Dynamic)
		{
			trace('Anti-aliasing: no mipmaps for ${graphic.key}: $e');
		}
	}

	static function hasExtension(gl:Dynamic, name:String):Bool
	{
		var list:Array<String> = gl.getSupportedExtensions();
		if (list != null) for (ext in list) if (ext == name || ext == 'GL_' + name) return true;
		return false;
	}

	public static function describe():String
	{
		if (!init()) return 'Anti-aliasing: software rendering';
		var msaa:String = msaaSamples > 1 ? '${msaaSamples}x MSAA ' + (msaaActive ? 'on' : 'off') : 'no MSAA on this GPU';
		var mips:String = mipmapsSupported ? (mipmapsActive ? 'mipmaps on' : 'mipmaps off') : 'no mipmaps on this GPU';
		var ss:String = supersamplingActive ? ', 2x2 supersampling on' : '';
		return 'Anti-aliasing: $msaa, $mips$ss  |  GPU: $renderer (OpenGL $glVersion)';
	}
}

private class MipmapEntry
{
	public var texture:TextureBase = null;
	public var version:Int = -2;
	public var ready:Bool = false;

	public function new() {}
}
