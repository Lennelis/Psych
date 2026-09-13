package shaders.freeplay;

import flixel.system.FlxAssets.FlxShader;

/**
 * Shifts a sprite's hue, saturation and value.
 *
 * V-Slice tints the freeplay capsules with this rather than with `color`, because a
 * flat tint would flatten the capsule's own shading - this keeps the highlight and the
 * shadow and only moves the colour underneath them.
 *
 * The glsl is V-Slice's `hsv.frag` verbatim. It is compiled in rather than loaded at
 * runtime: Psych can load `.frag` files, but only where runtime shaders are switched
 * on, and the capsules need this one wherever they are drawn.
 */
class HSVShader extends FlxShader
{
	public var hue(default, set):Float = 1;
	public var saturation(default, set):Float = 1;
	public var value(default, set):Float = 1;

	@:glFragmentSource('
		#pragma header

		uniform float _hue;
		uniform float _sat;
		uniform float _val;

		vec3 rgb2hsv(vec3 c)
		{
			vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
			vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
			vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
			float d = q.x - min(q.w, q.y);
			float e = 1.0e-10;
			return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
		}

		vec3 hsv2rgb(vec3 c)
		{
			vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
			vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
			return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
		}

		void main()
		{
			vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);
			vec4 swagColor = vec4(rgb2hsv(vec3(color[0], color[1], color[2])), color[3]);
			swagColor.x *= _hue;
			swagColor.y *= _sat;
			swagColor.z *= _val;
			// approximate "lightness" changing!!
			swagColor.z *= (_hue * 0.5) + 0.5;
			color = vec4(hsv2rgb(vec3(swagColor[0], swagColor[1], swagColor[2])), swagColor[3]);
			gl_FragColor = color;
		}
	')
	public function new(h:Float = 1, s:Float = 1, v:Float = 1)
	{
		super();

		hue = h;
		saturation = s;
		value = v;
	}

	function set_hue(value:Float):Float
	{
		_hue.value = [value];
		return this.hue = value;
	}

	function set_saturation(value:Float):Float
	{
		_sat.value = [value];
		return this.saturation = value;
	}

	function set_value(value:Float):Float
	{
		_val.value = [value];
		return this.value = value;
	}
}
