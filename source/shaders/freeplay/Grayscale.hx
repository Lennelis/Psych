package shaders.freeplay;

import flixel.system.FlxAssets.FlxShader;

/**
 * Drains the colour out of a sprite, `amount` being how far to take it.
 *
 * The freeplay capsules use it to grey out a song that has no score yet.
 *
 * V-Slice loads this one at runtime from `grayscale.frag`; the maths is unchanged,
 * but compiling it in means it works whether or not runtime shaders are switched on.
 */
class Grayscale extends FlxShader
{
	public var amount(default, set):Float = 1;

	@:glFragmentSource('
		#pragma header

		// Value from (0, 1)
		uniform float _amount;

		// Converts the input image to grayscale, with `_amount` representing the proportion
		// of the conversion. See https://drafts.fxtf.org/filter-effects/#grayscaleEquivalent
		vec4 to_grayscale(vec4 input_rgba)
		{
			float red = (0.2126 + 0.7874 * (1.0 - _amount)) * input_rgba.r + (0.7152 - 0.7152 * (1.0 - _amount)) * input_rgba.g + (0.0722 - 0.0722 * (1.0 - _amount)) * input_rgba.b;
			float green = (0.2126 - 0.2126 * (1.0 - _amount)) * input_rgba.r + (0.7152 + 0.2848 * (1.0 - _amount)) * input_rgba.g + (0.0722 - 0.0722 * (1.0 - _amount)) * input_rgba.b;
			float blue = (0.2126 - 0.2126 * (1.0 - _amount)) * input_rgba.r + (0.7152 - 0.7152 * (1.0 - _amount)) * input_rgba.g + (0.0722 + 0.9278 * (1.0 - _amount)) * input_rgba.b;

			return vec4(red, green, blue, input_rgba.a);
		}

		void main()
		{
			gl_FragColor = to_grayscale(flixel_texture2D(bitmap, openfl_TextureCoordv));
		}
	')
	public function new(amount:Float = 1)
	{
		super();
		this.amount = amount;
	}

	/** Kept for the sake of matching V-Slice, which calls this rather than assigning. */
	public inline function setAmount(value:Float):Void
		amount = value;

	function set_amount(value:Float):Float
	{
		_amount.value = [value];
		return amount = value;
	}
}
