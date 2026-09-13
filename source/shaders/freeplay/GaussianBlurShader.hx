package shaders.freeplay;

import flixel.system.FlxAssets.FlxShader;

/**
 * A cheap blur, used behind the freeplay capsule text and the rank badges to fake a glow.
 *
 * Not actually gaussian, as V-Slice's own comment says. Two 13-tap passes, one vertical
 * and one horizontal, mixed half and half - which is not a real separable blur either,
 * but it is what the menu was tuned against.
 *
 * V-Slice loads this from `gaussianBlur.frag` at runtime. Compiled in here so it works
 * with runtime shaders off, and with the dead accumulation loop dropped: the original
 * computes it into `blurred` and then never uses it.
 */
class GaussianBlurShader extends FlxShader
{
	public var amount(default, set):Float = 1;

	@:glFragmentSource('
		#pragma header

		uniform float _amount;

		vec4 blur13(sampler2D image, vec2 uv, vec2 resolution, vec2 direction)
		{
			vec4 color = vec4(0.0);
			vec2 off1 = vec2(1.411764705882353) * direction;
			vec2 off2 = vec2(3.2941176470588234) * direction;
			vec2 off3 = vec2(5.176470588235294) * direction;
			color += texture2D(image, uv) * 0.1964825501511404;
			color += texture2D(image, uv + (off1 / resolution)) * 0.2969069646728344;
			color += texture2D(image, uv - (off1 / resolution)) * 0.2969069646728344;
			color += texture2D(image, uv + (off2 / resolution)) * 0.09447039785044732;
			color += texture2D(image, uv - (off2 / resolution)) * 0.09447039785044732;
			color += texture2D(image, uv + (off3 / resolution)) * 0.010381362401148057;
			color += texture2D(image, uv - (off3 / resolution)) * 0.010381362401148057;
			return color;
		}

		void main()
		{
			vec4 blurred = blur13(bitmap, openfl_TextureCoordv, openfl_TextureSize.xy, vec2(0.0, _amount * 2.0));
			blurred = mix(blur13(bitmap, openfl_TextureCoordv, openfl_TextureSize.xy, vec2(_amount * 2.0, 0.0)), blurred, 0.5);
			gl_FragColor = blurred;
		}
	')
	public function new(amount:Float = 1.0)
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
