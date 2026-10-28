package objects;

import flixel.util.FlxColor;

class MenuButton extends FlxSpriteGroup
{
	public var optionName(default, null):String;
	public var highlight(default, null):Float = 0;
	public var baseX:Float = 0;
	public var introDelay:Float = 0;

	var wantSelected:Bool = false;
	var introTime:Float = 0;
	var pulseTime:Float = Math.random() * 6;
	var accentColor:Int;
	var w:Int;
	var h:Int;

	var glow:Array<FlxSprite> = [];
	var border:FlxSprite;
	var fill:FlxSprite;
	var accent:FlxSprite;
	var label:FlxText;
	var number:FlxText;
	var arrow:FlxText;
	var icon:FlxSprite;
	var introStyle:String = 'slide';
	var introSpeed:Float = 1;

	public function new(optionName:String, labelText:String, indexText:String, accentColor:Int, small:Bool = false, ?width:Int, ?height:Int)
	{
		super();
		this.optionName = optionName;
		this.accentColor = accentColor;
		w = (width != null) ? width : (small ? 300 : 470);
		h = (height != null) ? height : (small ? 54 : 76);

		for (i in 0...3)
		{
			var pad:Int = 5 + i * 5;
			var g:FlxSprite = new FlxSprite(-pad, -pad).makeGraphic(w + pad * 2, h + pad * 2, FlxColor.WHITE);
			g.color = accentColor;
			g.alpha = 0;
			add(g);
			glow.push(g);
		}

		border = new FlxSprite().makeGraphic(w, h, FlxColor.WHITE);
		border.color = MenuTheme.PANEL_BORDER_DIM;
		add(border);

		fill = new FlxSprite(2, 2).makeGraphic(w - 4, h - 4, FlxColor.WHITE);
		fill.color = MenuTheme.PANEL_FILL;
		fill.alpha = 0.7;
		add(fill);

		accent = new FlxSprite(2, 2).makeGraphic(small ? 6 : 8, h - 4, FlxColor.WHITE);
		accent.color = accentColor;
		add(accent);

		var size:Int = small ? 22 : 34;
		label = new FlxText(small ? 24 : 34, 0, w - 90, labelText.toUpperCase(), size);
		label.setFormat(MenuTheme.font(), size, MenuTheme.TEXT_DIM, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		while (label.textField.numLines > 1 && label.size > 12) label.size -= 1;
		label.y = (h - label.height) / 2;
		add(label);

		number = new FlxText(w - (small ? 80 : 100), 0, small ? 36 : 50, indexText, small ? 14 : 18);
		number.setFormat(MenuTheme.font(), small ? 14 : 18, MenuTheme.TEXT_DIM, RIGHT);
		number.y = (h - number.height) / 2;
		add(number);

		arrow = new FlxText(w - 30, 0, 24, '>', size);
		arrow.setFormat(MenuTheme.font(), size, accentColor, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		arrow.y = (h - arrow.height) / 2;
		arrow.alpha = 0;
		add(arrow);

		scrollFactor.set();
		for (m in members) m.scrollFactor.set();
		introStyle = MenuTheme.introStyle();
		introSpeed = MenuTheme.animSpeed();
		x = (introStyle == 'slide') ? -800 : baseX;
	}

	public function setIcon(spr:FlxSprite):Void
	{
		if (spr == null) return;
		var size:Float = h - 16;
		var s:Float = Math.min(size / spr.width, size / spr.height);
		spr.scale.set(s, s);
		spr.updateHitbox();
		spr.setPosition(18, (h - spr.height) / 2);
		icon = spr;
		add(spr);
		label.x += spr.width + 10;
		label.fieldWidth = Math.max(40, label.fieldWidth - spr.width - 10);
	}

	public function setSelected(sel:Bool):Void
		wantSelected = sel;

	public function midY():Float
		return y + h / 2;

	public function bounds():{x:Float, y:Float, w:Float, h:Float}
		return {x: x, y: y, w: w, h: h};

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		introTime += elapsed;
		pulseTime += elapsed;
		var target:Float = wantSelected ? 1 : 0;
		highlight += (target - highlight) * Math.min(1, elapsed * 12);
		if (Math.abs(target - highlight) < 0.002) highlight = target;

		var t:Float = (introStyle == 'none') ? 1 : Math.max(0, Math.min(1, (introTime * introSpeed - introDelay) / 0.55));
		var intro:Float = 1 - Math.pow(1 - t, 3);
		x = baseX + highlight * 36 - (introStyle == 'slide' ? (1 - intro) * 640 : 0);
		if (icon != null) icon.alpha = alpha * intro;

		var ga:Float = alpha;
		var pulse:Float = 0.5 + 0.5 * Math.sin(pulseTime * 3.2);
		border.color = FlxColor.interpolate(MenuTheme.PANEL_BORDER_DIM, accentColor, highlight);
		fill.alpha = (0.7 + 0.2 * highlight) * ga * intro;
		border.alpha = ga * intro;
		accent.alpha = (0.55 + 0.45 * highlight) * ga * intro;
		label.color = FlxColor.interpolate(MenuTheme.TEXT_DIM, MenuTheme.TEXT_BRIGHT, highlight);
		label.alpha = ga * intro;
		number.alpha = (0.45 + 0.4 * highlight) * ga * intro;
		arrow.alpha = highlight * ga * intro;
		arrow.x = x + w - 30 - 4 * pulse * highlight;
		for (i in 0...glow.length)
			glow[i].alpha = highlight * (0.06 + 0.05 * pulse) * (1 - i * 0.22) * ga * intro;
	}
}
