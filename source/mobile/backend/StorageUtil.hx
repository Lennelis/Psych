package mobile.backend;

#if android
// extension-androidtools 2.x moved these out of the `android` package, which is
// where Psych's own Main.hx used to import them from.
import extension.androidtools.content.Context;
// VERSION and VERSION_CODES are their own classes inside the Build module, not fields
// of Build, so they have to be imported by name.
import extension.androidtools.os.Build.VERSION;
import extension.androidtools.os.Build.VERSION_CODES;
import extension.androidtools.os.Environment;
import extension.androidtools.Permissions;
import extension.androidtools.Settings;
#end
import haxe.io.Path;
import openfl.utils.Assets;

/**
 * Where the game keeps its writable files on a phone.
 *
 * On Android that is `/storage/emulated/0/.PsychEngine/`, which `Main` makes the
 * working directory on startup, so every relative path Psych already uses - `mods/`,
 * `modsList.txt`, `crash/` - lands somewhere a file manager can reach. Mods are no use
 * if you can't put them there, and the app's own folder under `Android/data` stopped
 * being browsable on Android 11.
 *
 * The leading dot keeps the whole tree out of galleries and music players, which would
 * otherwise index every mod's artwork and every song in it. A `.nomedia` file goes in
 * as well: the dot is a convention media scanners respect, `.nomedia` is the part
 * that's actually specified.
 *
 * Reaching shared storage needs permission, and the app can't help being told no. Every
 * path here falls back to the private folder the port used before, which needs no
 * permission and always works - the game runs either way, it's only the mods that
 * become hard to install.
 */
class StorageUtil
{
	/** The folder in shared storage, dot-prefixed so scanners skip the lot. */
	public static inline var FOLDER_NAME:String = '.PsychEngine';

	/** Resolved once: the probe writes a file, and that isn't worth doing per call. */
	static var cachedDirectory:String = null;

	/** True when the game is running out of shared storage rather than its own folder. */
	public static var usingSharedStorage(default, null):Bool = false;

	/** Writable root, with a trailing slash. Matches the working directory `Main` sets. */
	public static function getStorageDirectory():String
	{
		if (cachedDirectory != null) return cachedDirectory;

		#if android
		cachedDirectory = resolveAndroidDirectory();
		#elseif ios
		cachedDirectory = Path.addTrailingSlash(lime.system.System.applicationStorageDirectory);
		#else
		cachedDirectory = Path.addTrailingSlash(Sys.getCwd());
		#end

		return cachedDirectory;
	}

	#if android
	/** The app's own folder, which is always writable and never needs asking. */
	static function getPrivateDirectory():String
	{
		// The JNI call hands back an empty string if it can't reach the Java side.
		// Left alone that becomes "/", and the game would try to run out of the
		// filesystem root.
		final external:String = Context.getExternalFilesDir();
		if (external != null && external.length > 0) return Path.addTrailingSlash(external);

		return Path.addTrailingSlash(lime.system.System.applicationStorageDirectory);
	}

	static function resolveAndroidDirectory():String
	{
		final shared:String = Environment.getExternalStorageDirectory();

		if (shared != null && shared.length > 0)
		{
			final folder:String = Path.addTrailingSlash(Path.addTrailingSlash(shared) + FOLDER_NAME);

			if (canWriteTo(folder))
			{
				usingSharedStorage = true;
				writeNoMedia(folder);
				return folder;
			}
		}

		trace('StorageUtil: no access to shared storage, mods will live in the app folder instead');
		return getPrivateDirectory();
	}

	/**
	 * Asks for whatever reaching shared storage takes on this version of Android.
	 *
	 * Android 11 replaced the old write permission with All files access, which is a
	 * settings page rather than a dialog - the app carries on running while the player
	 * is over there, and what they choose only takes effect on the next launch, because
	 * the working directory is fixed at startup.
	 *
	 * Worth knowing: `Permissions.getGrantedPermissions` in extension-androidtools is
	 * broken - it looks up `requestPermissions`, signature and all, then calls it with
	 * no arguments - so this never asks Android what it granted. It writes a file and
	 * sees whether that worked, which is the question it actually wants answered.
	 */
	public static function requestStorageAccess():Void
	{
		if (usingSharedStorage || cachedDirectory == null) return; // already in, or nothing tried yet

		try
		{
			if (VERSION.SDK_INT >= VERSION_CODES.R)
				Settings.requestSetting('MANAGE_ALL_FILES_ACCESS_PERMISSION');
			else
				Permissions.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);
		}
		catch (e:Dynamic)
			trace('StorageUtil: could not ask for storage access ($e)');
	}

	/** Makes the folder and writes a file in it, because nothing else proves it's writable. */
	static function canWriteTo(folder:String):Bool
	{
		try
		{
			if (!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
			if (!FileSystem.isDirectory(folder)) return false;

			final probe:String = folder + '.write-test';
			File.saveContent(probe, '');
			FileSystem.deleteFile(probe);
			return true;
		}
		catch (e:Dynamic)
			return false;
	}

	/** The file that keeps galleries and music players out of a folder. */
	static function writeNoMedia(folder:String):Void
	{
		final marker:String = folder + '.nomedia';
		if (FileSystem.exists(marker)) return;

		try
		{
			File.saveContent(marker, '');
		}
		catch (e:Dynamic)
			trace('StorageUtil: could not write .nomedia ($e)');
	}
	#end

	/**
	 * Unpacks the mods that ship inside the app onto storage, once.
	 *
	 * On desktop `example_mods` is a `template`, so it lands next to the executable
	 * and `Mods` can just read it. There's no such folder on a phone, the files are
	 * sealed inside the APK, so they have to be written out before `Mods` looks for
	 * them. Existing files are never overwritten, otherwise an update would wipe
	 * whatever the player edited.
	 */
	public static function unpackBundledFiles():Void
	{
		#if (mobile && MODS_ALLOWED)
		final root:String = getStorageDirectory();

		for (id in Assets.list())
		{
			if (id != 'modsList.txt' && !id.startsWith('mods/')) continue;

			final target:String = root + id;
			if (FileSystem.exists(target)) continue;

			try
			{
				final directory:String = Path.directory(target);
				if (directory.length > 0 && !FileSystem.exists(directory)) FileSystem.createDirectory(directory);

				File.saveBytes(target, Assets.getBytes(id));
			}
			catch (e:Dynamic)
				trace('StorageUtil: failed to unpack "$id" ($e)');
		}

		// Somewhere obvious to drop a mod folder, even before there is one to unpack.
		ensureDirectory(root + 'mods');
		#end
	}

	/** Makes sure a folder the game writes to exists. */
	public static function ensureDirectory(path:String):Bool
	{
		#if sys
		try
		{
			if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
			return true;
		}
		catch (e:Dynamic)
		{
			trace('StorageUtil: could not create "$path" ($e)');
			return false;
		}
		#else
		return false;
		#end
	}
}
