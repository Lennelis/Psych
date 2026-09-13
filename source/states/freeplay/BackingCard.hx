package states.freeplay;

import flixel.group.FlxSpriteGroup;
import flixel.util.FlxSpriteUtil;
import openfl.display.BlendMode;

/**
 * The pink card the freeplay menu is drawn on.
 *
 * Ported from V-Slice's `BackingCard`, minus the scripting hooks it implements for
 * mods and the per-character variants, which are a later job. What is here is the
 * default card: the pink slab that slides in from the left, the orange strip across
 * it that only shows where the slab does, the glows that fire when a song is picked,
 * and the "yeah" text scrolling behind it.
 *
 * V-Slice's version of the scrolling text is an Animate atlas. This one is
 * `BGScrollingText` reading the same words, because the atlas is a single asset baked
 * at 1280 and the text can be rebuilt at whatever width the screen turns out to be.
 */
class BackingCard extends FlxSpriteGroup
{
	/** Share of the extra width the things near the DJ move right by. V-Slice's number. */
	public static final DJ_POS_MULTI:Float = 0.44;

	public var pinkBack:FlxSprite;
	public var orangeBackShit:FlxSprite;
	public var alsoOrangeLOL:FlxSprite;
	public var confirmGlow:FlxSprite;
	public var confirmGlow2:FlxSprite;
	public var confirmTextGlow:FlxSprite;
	public var cardGlow:FlxSprite;
	public var backingTextYeah:BGScrollingText;

	/**
	 * How much wider than 16:9 the screen is, divided by 1.5 - V-Slice's `CUTOUT_WIDTH`.
	 *
	 * The menu is built for 1280 and everything on the left of it moves right by a share
	 * of this on a wider screen, so the card, the songs and the difficulty don't stay
	 * huddled against the left edge with the art stranded in the middle.
	 */
	public var cutout(default, null):Float;

	public function new(cutout:Float = 0)
	{
		super();

		this.cutout = cutout;

		cardGlow = new FlxSprite(-30, -30).loadGraphic(Paths.image('freeplay/cardGlow'));
		cardGlow.blend = BlendMode.ADD;
		cardGlow.visible = false;

		confirmGlow = new FlxSprite(-30, 240).loadGraphic(Paths.image('freeplay/confirmGlow'));
		confirmGlow.blend = BlendMode.ADD;
		confirmGlow.visible = false;

		confirmGlow2 = new FlxSprite(confirmGlow.x, confirmGlow.y).loadGraphic(Paths.image('freeplay/confirmGlow2'));
		confirmGlow2.visible = false;

		confirmTextGlow = new FlxSprite(-8, 115).loadGraphic(Paths.image('freeplay/glowingText'));
		confirmTextGlow.blend = BlendMode.ADD;
		confirmTextGlow.visible = false;

		pinkBack = new FlxSprite().loadGraphic(Paths.image('freeplay/pinkBack'));
		pinkBack.color = 0xFFFFD4E9; // sets it to pink!

		// Stretched to cover the extra width, like V-Slice does. The diagonal on its
		// right gets shallower, which nothing can see: the art on the right is drawn
		// over that part of it.
		if (cutout > 0)
		{
			pinkBack.scale.x = (pinkBack.frameWidth + cutout) / pinkBack.frameWidth;
			pinkBack.updateHitbox();
		}

		pinkBack.x -= pinkBack.width; // starts off to the left, and slides in

		// Built at the card's own width rather than its stretched one, so it lines up
		// with the mask below - which is the card's pixels, and those never stretched.
		orangeBackShit = new FlxSprite(84, 440).makeGraphic(pinkBack.frameWidth, 75, 0xFFFEDA00);
		alsoOrangeLOL = new FlxSprite(0, orangeBackShit.y).makeGraphic(100, Std.int(orangeBackShit.height), 0xFFFFD400);

		confirmGlow.x += cutout * DJ_POS_MULTI;
		confirmGlow2.x += cutout * DJ_POS_MULTI;
		confirmTextGlow.x += cutout * DJ_POS_MULTI;

		backingTextYeah = new BGScrollingText((cutout * DJ_POS_MULTI) - 320, 120, 'RIGHT HERE, RIGHT NOW, YEAH!', FlxG.width, true, 60);
		backingTextYeah.speed = 2.4;
		// Darker than the card rather than brighter: V-Slice's is a drawn texture that
		// reads as an inset shadow, and yellow on yellow simply disappeared.
		backingTextYeah.color = 0xFFE2B830;
	}

	/** Adds everything in the order it has to be drawn, and starts the card sliding in. */
	public function build():Void
	{
		FlxTween.tween(pinkBack, {x: 0}, 0.6, {ease: FlxEase.quartOut});
		add(pinkBack);

		add(orangeBackShit);
		add(alsoOrangeLOL);

		// The orange strip is only allowed to show where the pink slab is, so the slab is
		// used as its mask - which is what keeps it from running off the side of the card.
		FlxSpriteUtil.alphaMaskFlxSprite(orangeBackShit, pinkBack, orangeBackShit);
		orangeBackShit.visible = false;
		alsoOrangeLOL.visible = false;

		add(confirmGlow2);
		add(confirmGlow);
		add(confirmTextGlow);
		add(backingTextYeah);
		add(cardGlow);
	}

	/**
	 * Says where the card's pieces go when the menu is left.
	 *
	 * V-Slice only lists the slab and the orange strip here, because its state switches
	 * a fraction of a second later and nothing else has time to be noticed. Psych's
	 * transition is slower, and the scrolling text left hanging on an empty screen was
	 * very noticeable, so the whole card is listed.
	 */
	public function applyExitMovers(exitMovers:states.freeplay.VSliceFreeplayState.ExitMoverData):Void
	{
		exitMovers.set([
			pinkBack,
			orangeBackShit,
			alsoOrangeLOL,
			backingTextYeah,
			confirmGlow,
			confirmGlow2,
			confirmTextGlow,
			cardGlow
		], {
			x: -pinkBack.width,
			speed: 0.4,
			wait: 0
		});
	}

	/** Snaps the card home, for when the menu is entered without its intro. */
	public function skipIntroTween():Void
	{
		FlxTween.cancelTweensOf(pinkBack);
		pinkBack.x = 0;
	}

	/** Called once the intro is over: the card goes yellow and the glow flares out. */
	public function introDone():Void
	{
		pinkBack.color = 0xFFFFD863;
		orangeBackShit.visible = true;
		alsoOrangeLOL.visible = true;
		cardGlow.visible = true;
		FlxTween.tween(cardGlow, {alpha: 0, 'scale.x': 1.2, 'scale.y': 1.2}, 0.45, {ease: FlxEase.sineOut});
	}

	/** Called when a song is picked: the card darkens and the glows fire in sequence. */
	public function confirm():Void
	{
		FlxTween.color(pinkBack, 0.33, 0xFFFFD0D5, 0xFF171831, {ease: FlxEase.quadOut});
		orangeBackShit.visible = false;
		alsoOrangeLOL.visible = false;

		confirmGlow.visible = true;
		confirmGlow2.visible = true;
		confirmGlow2.alpha = 0;
		confirmGlow.alpha = 0;

		FlxTween.tween(confirmGlow2, {alpha: 0.5}, 0.33, {
			ease: FlxEase.quadOut,
			onComplete: function(_)
			{
				confirmGlow2.alpha = 0.6;
				confirmGlow.alpha = 1;
				confirmTextGlow.visible = true;
				confirmTextGlow.alpha = 1;
				FlxTween.tween(confirmTextGlow, {alpha: 0.4}, 0.5);
				FlxTween.tween(confirmGlow, {alpha: 0}, 0.5);
			}
		});
	}

	/** Called on the way out of the menu. */
	public function disappear():Void
	{
		FlxTween.color(pinkBack, 0.25, 0xFFFFD863, 0xFFFFD0D5, {ease: FlxEase.quadOut});

		cardGlow.visible = true;
		cardGlow.alpha = 1;
		cardGlow.scale.set(1, 1);
		FlxTween.tween(cardGlow, {alpha: 0, 'scale.x': 1.2, 'scale.y': 1.2}, 0.25, {ease: FlxEase.sineOut});

		orangeBackShit.visible = false;
		alsoOrangeLOL.visible = false;
	}
}
