package states.editors.content;

import flixel.addons.display.FlxGridOverlay;

// Laggier than a single sprite for the grid, but this is to avoid having to re-create the sprite constantly
class ChartingGridSprite extends FlxSprite
{
	public var rows(default, set):Float = 16;
	public var columns(default, null):Int = 0;
	public var spacing(default, set):Int = 0;
	public var stripe:FlxSprite;
	public var stripes:Array<Int>;

	var vortexLine:FlxSprite;
	public var vortexLineEnabled:Bool = false;
	public var vortexLineSpace:Float = 0;

	/**
	 * Where each section begins, in pixels from the top of the grid.
	 *
	 * The grid used to be three sprites, one per section, so a section boundary was just
	 * where one sprite ended and the next began. One continuous grid has no such seam, and
	 * sections still matter - they carry mustHitSection, the BPM changes, the beat count -
	 * so they get drawn.
	 */
	public var sectionLines:Array<Float> = [];

	/** Whether to draw them. Toggled from the editor's grid options. */
	public var drawSectionLines:Bool = true;

	var sectionLine:FlxSprite;

	public function new(columns:Int, ?color1:FlxColor = 0xFFE6E6E6, ?color2:FlxColor = 0xFFD8D8D8)
	{
		super();
		this.columns = columns;
		scrollFactor.x = 0;
		active = false;

		scale.set(ChartingState.GRID_SIZE, ChartingState.GRID_SIZE);
		loadGrid(color1, color2);
		updateHitbox();
		recalcHeight();

		vortexLine = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		vortexLine.scale.x = this.width;
		vortexLine.scrollFactor.x = 0;
		vortexLine.color = 0xFF660000;
		vortexLine.updateHitbox();

		stripe = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		stripe.scrollFactor.x = 0;
		stripe.color = FlxColor.BLACK;

		sectionLine = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		sectionLine.scale.x = this.width;
		sectionLine.scrollFactor.x = 0;
		sectionLine.color = 0xFF222222;
		sectionLine.updateHitbox();

		updateStripes();
	}

	public function loadGrid(color1:FlxColor, color2:FlxColor)
	{
		loadGraphic(FlxGridOverlay.createGrid(1, 1, columns, 2, true, color1, color2), true, columns, 1);
		animation.add('odd', [0], false);
		animation.add('even', [1], false);
		animation.play('even', true);
		updateHitbox();
		recalcHeight();
	}

	override function draw()
	{
		if(!visible || alpha == 0 || y - camera.scroll.y >= FlxG.height) return;

		var step:Float = ChartingState.GRID_SIZE + spacing;
		var initialY:Float = y;
		var total:Int = Math.ceil(rows);

		// A grid spanning a whole song is tens of thousands of rows tall and nearly all of
		// them are above the viewport. Starting at row zero and walking down until one
		// lands on screen is what would make that unusable; this starts at the first row
		// that could be seen and stops at the first one that can't.
		var first:Int = 0;
		if(step > 0 && y < camera.scroll.y) first = Math.floor((camera.scroll.y - y) / step);

		if(first < total)
		{
			y = initialY + first * step;
			for (i in first...total)
			{
				if(y - camera.scroll.y >= FlxG.height) break;

				animation.play((i % 2 == 1) ? 'odd' : 'even', true);
				scale.y = ChartingState.GRID_SIZE * Math.min(1, rows - i);
				offset.y = -0.5 * (scale.y - 1);
				super.draw();

				y += step;
			}
			animation.play('even', true);
			y = initialY;
		}

		_drawStripes();
		_drawSectionLines();

		if(vortexLineEnabled && vortexLineSpace > 0)
		{
			vortexLine.x = this.x;

			// Same reasoning as the rows above: skip straight to the first line that could
			// be on screen rather than counting up to it one beat at a time.
			var skipped:Float = Math.max(0, Math.ffloor((camera.scroll.y - this.y) / vortexLineSpace));
			vortexLine.y = this.y - 1 + skipped * vortexLineSpace;

			var bottom:Float = this.y + this.height;
			while (true)
			{
				vortexLine.y += vortexLineSpace;
				if(vortexLine.y >= bottom || vortexLine.y - camera.scroll.y >= FlxG.height) break;

				vortexLine.draw();
			}
		}
	}

	function _drawSectionLines()
	{
		if(!drawSectionLines || sectionLines == null || sectionLines.length == 0) return;

		var top:Float = camera.scroll.y;
		var bottom:Float = top + FlxG.height;

		sectionLine.x = this.x;
		for (offsetY in sectionLines)
		{
			var lineY:Float = this.y + offsetY;
			if(lineY < top) continue;
			if(lineY >= bottom) break;

			sectionLine.y = lineY;
			sectionLine.draw();
		}
	}

	function _drawStripes()
	{
		if(stripes == null) return;

		// Sized to the viewport rather than to the grid. The grid is now as long as the
		// song, and asking the renderer to scale a 1x1 pixel to a few hundred thousand
		// tall is asking for precision artifacts for no benefit - nobody can see past the
		// bottom of the screen anyway.
		var top:Float = Math.max(this.y, camera.scroll.y);
		var bottom:Float = Math.min(this.y + this.height, camera.scroll.y + FlxG.height);
		if(bottom <= top) return;

		stripe.y = top;
		stripe.setGraphicSize(2, bottom - top);
		stripe.updateHitbox();

		for (i => column in stripes)
		{
			if(column == 0)
				stripe.x = this.x;
			else 
				stripe.x = this.x + ChartingState.GRID_SIZE * column - stripe.width/2;
			stripe.draw();
		}
	}

	public function updateStripes()
	{
		if(stripe == null || !stripe.exists) return;
		stripe.y = this.y;
	}

	function set_rows(v:Float)
	{
		rows = v;
		recalcHeight();
		return rows;
	}

	function set_spacing(v:Int)
	{
		spacing = v;
		recalcHeight();
		return spacing;
	}

	function recalcHeight()
	{
		height = ((ChartingState.GRID_SIZE + spacing) * rows) - spacing;
		updateStripes();
	}
}