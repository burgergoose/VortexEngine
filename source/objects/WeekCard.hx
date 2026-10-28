package objects;

import flixel.util.FlxColor;
import objects.MenuItem;

class WeekCard extends FlxSpriteGroup
{
	public static inline var CARD_WIDTH:Int = 620;
	public static inline var CARD_HEIGHT:Int = 130;
	static inline var BORDER:Int = 2;

	public var weekFile(default, null):String;
	public var bannerItem(default, null):MenuItem;
	public var targetY:Float = 0;

	var border:FlxSprite;
	var fill:FlxSprite;
	var accentBar:FlxSprite;
	var lockedOverlay:FlxSprite;
	var lockIcon:FlxSprite;
	var titleFallback:FlxText;

	public var highlight(default, null):Float = 0;
	var wantSelected:Bool = false;
	var glow:Array<FlxSprite> = [];
	var pulseTime:Float = 0;

	public function new(weekFile:String, weekName:String, displayName:String = '')
	{
		super();
		this.weekFile = weekFile;

		for (i in 0...3)
		{
			var pad:Int = 5 + i * 5;
			var g:FlxSprite = new FlxSprite(-pad, -pad).makeGraphic(CARD_WIDTH + pad * 2, CARD_HEIGHT + pad * 2, FlxColor.WHITE);
			g.color = MenuTheme.PANEL_BORDER_BRIGHT;
			g.alpha = 0;
			add(g);
			glow.push(g);
		}

		border = new FlxSprite().makeGraphic(CARD_WIDTH, CARD_HEIGHT, FlxColor.WHITE);
		border.color = MenuTheme.PANEL_BORDER_DIM;
		add(border);

		fill = new FlxSprite(BORDER, BORDER).makeGraphic(CARD_WIDTH - BORDER * 2, CARD_HEIGHT - BORDER * 2, FlxColor.WHITE);
		fill.color = MenuTheme.PANEL_FILL;
		fill.alpha = 0.68;
		add(fill);

		accentBar = new FlxSprite(BORDER, BORDER).makeGraphic(6, CARD_HEIGHT - BORDER * 2, FlxColor.WHITE);
		accentBar.color = MenuTheme.PANEL_BORDER_BRIGHT;
		accentBar.visible = false;
		add(accentBar);

		bannerItem = new MenuItem(0, 0, weekName);
		var maxW:Float = CARD_WIDTH - 40;
		var maxH:Float = CARD_HEIGHT - 30;
		if (bannerItem.width > 0 && bannerItem.height > 0)
		{
			var scale:Float = Math.min(maxW / bannerItem.width, maxH / bannerItem.height);
			if (scale < 1)
			{
				bannerItem.setGraphicSize(Math.floor(bannerItem.width * scale), Math.floor(bannerItem.height * scale));
				bannerItem.updateHitbox();
			}
		}
		bannerItem.x = (CARD_WIDTH - bannerItem.width) / 2;
		bannerItem.y = (CARD_HEIGHT - bannerItem.height) / 2;
		bannerItem.scrollFactor.set();
		add(bannerItem);

		var hasBanner:Bool = bannerItem.graphic != null && bannerItem.frameWidth > 2 && bannerItem.frameHeight > 2;
		if (!hasBanner)
		{
			bannerItem.visible = false;
			var label:String = displayName.length > 0 ? displayName : weekFile;
			titleFallback = new FlxText(BORDER + 16, 0, CARD_WIDTH - 40, label.toUpperCase(), 40);
			titleFallback.setFormat(MenuTheme.font(), 40, MenuTheme.TEXT_BRIGHT, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			titleFallback.borderSize = 2;
			titleFallback.y = (CARD_HEIGHT - titleFallback.height) / 2;
			add(titleFallback);
		}

		lockedOverlay = new FlxSprite(BORDER, BORDER).makeGraphic(CARD_WIDTH - BORDER * 2, CARD_HEIGHT - BORDER * 2, FlxColor.BLACK);
		lockedOverlay.alpha = 0.55;
		lockedOverlay.visible = false;
		add(lockedOverlay);

		lockIcon = new FlxSprite(CARD_WIDTH - 44, CARD_HEIGHT - 44);
		lockIcon.frames = Paths.getSparrowAtlas('campaign_menu_UI_assets');
		lockIcon.animation.addByPrefix('lock', 'lock');
		lockIcon.animation.play('lock');
		lockIcon.setGraphicSize(30, 30);
		lockIcon.updateHitbox();
		lockIcon.scrollFactor.set();
		lockIcon.visible = false;
		add(lockIcon);

		setLocked(false);
		setSelected(false);
	}

	public var classicMode(default, null):Bool = false;
	public function setClassic(on:Bool):Void
	{
		classicMode = on;
		if (titleFallback != null) titleFallback.color = on ? FlxColor.WHITE : MenuTheme.TEXT_BRIGHT;
	}

	public function setLocked(locked:Bool):Void
	{
		lockIcon.visible = locked;
		lockedOverlay.visible = locked;
	}

	public function setSelected(sel:Bool):Void
	{
		wantSelected = sel;
		accentBar.visible = true;
	}

	public function selectNudge():Float
		return highlight * 26;

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		pulseTime += elapsed;
		var target:Float = wantSelected ? 1 : 0;
		highlight += (target - highlight) * Math.min(1, elapsed * 12);
		if (Math.abs(target - highlight) < 0.002) highlight = target;

		var ga:Float = alpha;
		var pulse:Float = 0.5 + 0.5 * Math.sin(pulseTime * 3.2);
		if (classicMode)
		{
			border.alpha = fill.alpha = accentBar.alpha = 0;
			for (g in glow) g.alpha = 0;
			bannerItem.alpha = ga;
			if (titleFallback != null) titleFallback.alpha = ga;
			lockedOverlay.alpha = 0;
			lockIcon.alpha = ga;
			return;
		}
		border.color = FlxColor.interpolate(MenuTheme.PANEL_BORDER_DIM, MenuTheme.PANEL_BORDER_BRIGHT, highlight);
		border.alpha = ga;
		bannerItem.alpha = ga;
		if (titleFallback != null) titleFallback.alpha = ga;
		lockedOverlay.alpha = 0.55 * ga;
		lockIcon.alpha = ga;
		fill.alpha = (0.6 + 0.26 * highlight) * ga;
		accentBar.alpha = highlight * ga;
		for (i in 0...glow.length)
			glow[i].alpha = highlight * (0.05 + 0.04 * pulse) * (1 - i * 0.22) * ga;
	}
}
