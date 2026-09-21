package mobile.backend;

#if android
import lime.system.JNI;
import lime.system.JNI.JNIStaticField;
#end

/**
 * What the device takes out of its own screen: the notch, the punch hole, the rounded
 * corners.
 *
 * Android reports these as safe insets - how far in from each edge you have to stay to be
 * sure of being seen. They are read straight out of the platform through JNI rather than
 * through a Java helper added to the build, because that would mean carrying an Android
 * template and a source set for four numbers.
 *
 * Everything here is in device pixels. `WidescreenScaleMode` turns them into the game's own
 * coordinates, which is where anything laying out against them should read them from.
 *
 * Every step is allowed to fail. `getRootWindowInsets` arrived in API 23 and
 * `getDisplayCutout` in API 28, a phone with no cutout returns null from the latter, and the
 * view has no insets at all until it is attached - so the honest answer to most of those is
 * zero, and none of them is worth a crash. On anything that isn't Android it is always zero.
 */
class ScreenUtil
{
	public static var left(default, null):Float = 0;
	public static var top(default, null):Float = 0;
	public static var right(default, null):Float = 0;
	public static var bottom(default, null):Float = 0;

	/** True once the platform has actually answered, so a zero means no cutout. */
	public static var measured(default, null):Bool = false;

	/**
	 * Asks the platform again.
	 *
	 * Worth doing on a resize as well as at startup: the insets swap sides when the phone is
	 * turned round, and they are not available at all until the view is attached.
	 */
	public static function refresh():Void
	{
		#if android
		try
		{
			var viewField:JNIStaticField = JNI.createStaticField('org/haxe/extension/Extension', 'mainView', 'Landroid/view/View;');
			if (viewField == null) return;

			var view:Dynamic = viewField.get();
			if (view == null) return;

			var getInsets:Dynamic = JNI.createMemberMethod('android/view/View', 'getRootWindowInsets', '()Landroid/view/WindowInsets;', false, true);
			if (getInsets == null) return;

			var insets:Dynamic = getInsets(view);
			if (insets == null) return;

			var getCutout:Dynamic = JNI.createMemberMethod('android/view/WindowInsets', 'getDisplayCutout', '()Landroid/view/DisplayCutout;', false, true);
			if (getCutout == null) return;

			var cutout:Dynamic = getCutout(insets);

			// No cutout is a null here, and a perfectly ordinary answer - a phone with a flat
			// top edge. Said so, so nothing goes on asking every frame.
			measured = true;

			if (cutout == null)
			{
				left = top = right = bottom = 0;
				return;
			}

			left = safeInset(cutout, 'getSafeInsetLeft');
			top = safeInset(cutout, 'getSafeInsetTop');
			right = safeInset(cutout, 'getSafeInsetRight');
			bottom = safeInset(cutout, 'getSafeInsetBottom');

			// Said once, so a phone that is laying things out oddly can be checked against what
			// the device actually reported without a debug build.
			trace('ScreenUtil: display cutout insets $left, $top, $right, $bottom (device pixels)');
		}
		catch (e:Dynamic)
			trace('ScreenUtil: could not read the display cutout ($e)');
		#else
		// Nothing else reports one, so there is nothing to keep asking for.
		measured = true;
		#end
	}

	#if android
	static function safeInset(cutout:Dynamic, method:String):Float
	{
		var read:Dynamic = JNI.createMemberMethod('android/view/DisplayCutout', method, '()I', false, true);
		if (read == null) return 0;

		var value:Null<Int> = read(cutout);
		return (value == null) ? 0 : value;
	}
	#end
}
