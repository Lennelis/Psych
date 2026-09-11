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

	/**
	 * One line about where the game is reading and writing, for the mobile options menu.
	 *
	 * Nothing about storage access is visible from inside the game otherwise - the folder
	 * is picked before the first frame and never mentioned again - so when a device won't
	 * hand over shared storage there's no way to tell that from the game simply not asking.
	 */
	public static function describe():String
	{
		final folder:String = getStorageDirectory();

		#if android
		if (usingSharedStorage) return 'Mods live in $folder';

		var text:String = 'No luck writing to shared storage, so mods live in\n$folder\nwhich a file manager can only reach before Android 11.';
		text += '\nAndroid says all files access is ' + (hasAllFilesAccess() ? 'granted' : 'not granted') + '.';
		if (lastRequest != null) text += ' Last asked for $lastRequest.';
		return text;
		#else
		return 'Files live in $folder';
		#end
	}

	#if android
	/** What the last request actually asked Android for, since none of it reports back. */
	public static var lastRequest(default, null):String = null;

	/** Flipped once a request has been made, so a second press tries the other way in. */
	static var askedOnce:Bool = false;

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

	/**
	 * Where shared storage is mounted.
	 *
	 * `Environment.getExternalStorageDirectory` is the answer Android itself gives, but it
	 * is a JNI call, and every JNI call in the extension returns an empty string rather
	 * than an error when it can't reach the Java side. The rest of the list is the same
	 * path spelled the ways it has been spelled since Android 4, so a JNI failure costs
	 * the mods folder nothing.
	 */
	static function sharedRoot():String
	{
		final candidates:Array<String> = [];

		try
		{
			candidates.push(Environment.getExternalStorageDirectory());
		}
		catch (e:Dynamic)
			trace('StorageUtil: Environment.getExternalStorageDirectory failed ($e)');

		candidates.push(Sys.getEnv('EXTERNAL_STORAGE'));
		candidates.push('/storage/emulated/0');
		candidates.push('/sdcard');

		for (path in candidates)
		{
			if (path == null || path.length == 0) continue;

			try
			{
				if (FileSystem.exists(path) && FileSystem.isDirectory(path)) return path;
			}
			catch (e:Dynamic) {}
		}

		return null;
	}

	/** The folder the game wants in shared storage, whether or not it can be written to. */
	public static function sharedFolder():String
	{
		final root:String = sharedRoot();
		if (root == null) return null;

		return Path.addTrailingSlash(Path.addTrailingSlash(root) + FOLDER_NAME);
	}

	static function resolveAndroidDirectory():String
	{
		final folder:String = sharedFolder();

		if (folder != null && canWriteTo(folder))
		{
			usingSharedStorage = true;
			writeNoMedia(folder);
			return folder;
		}

		trace('StorageUtil: no access to shared storage, mods will live in the app folder instead');
		usingSharedStorage = false;
		return getPrivateDirectory();
	}

	/**
	 * Looks again, and moves the game over if shared storage opened up.
	 *
	 * All files access is granted on a settings page, not in a dialog, so the game is
	 * still running while it happens and gets no result back. Re-resolving when focus
	 * comes back means the grant takes effect there and then instead of next launch.
	 *
	 * @return whether the game is on shared storage now.
	 */
	public static function refresh():Bool
	{
		if (usingSharedStorage) return true;

		final previous:String = cachedDirectory;
		cachedDirectory = null;
		final folder:String = getStorageDirectory();

		if (!usingSharedStorage || folder == previous) return usingSharedStorage;

		Sys.setCwd(folder);
		unpackBundledFiles();

		#if MODS_ALLOWED
		// The mods list was read out of the old folder, so everything about it is stale.
		Mods.updatedOnState = false;
		Mods.pushGlobalMods();
		Mods.loadTopMod();
		#end

		trace('StorageUtil: moved to $folder');
		return true;
	}

	/** True when Android says the app may reach shared storage, going by Android not a probe. */
	public static function hasAllFilesAccess():Bool
	{
		try
		{
			return Environment.isExternalStorageManager();
		}
		catch (e:Dynamic)
			return false;
	}

	/**
	 * Asks for whatever reaching shared storage takes on this version of Android.
	 *
	 * Android 11 replaced the old write permission with All files access, which is a
	 * settings page rather than a dialog - the app carries on running while the player
	 * is over there, so `refresh` runs when focus comes back to pick up a grant without
	 * needing a restart.
	 *
	 * Two things here are worked around rather than trusted. `VERSION.SDK_INT` is a JNI
	 * call that gives 0 when it fails, and 0 would send the request down the pre-Android
	 * 11 path, where asking for WRITE_EXTERNAL_STORAGE on a modern phone is refused
	 * without ever showing a dialog - so an unreadable version is treated as new. And
	 * there are two settings pages for All files access, the per-app one and the list of
	 * every app; `requestSetting` returns nothing whether it opened one or threw, so a
	 * second press tries the other.
	 *
	 * Worth knowing: `Permissions.getGrantedPermissions` in extension-androidtools is
	 * broken - it looks up `requestPermissions`, signature and all, then calls it with
	 * no arguments - so there is no asking Android what it granted that way.
	 */
	public static function requestStorageAccess():Void
	{
		if (usingSharedStorage) return; // already in

		getStorageDirectory(); // so a probe that just works never bothers the player
		if (usingSharedStorage) return;

		var sdk:Int = 0;
		try
		{
			sdk = VERSION.SDK_INT;
		}
		catch (e:Dynamic)
			trace('StorageUtil: could not read the Android version ($e)');

		try
		{
			if (sdk <= 0 || sdk >= VERSION_CODES.R)
			{
				final setting:String = askedOnce ? 'MANAGE_ALL_FILES_ACCESS_PERMISSION' : 'MANAGE_APP_ALL_FILES_ACCESS_PERMISSION';
				lastRequest = 'android.settings.$setting';
				Settings.requestSetting(setting);
			}
			else
			{
				lastRequest = 'READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE';
				Permissions.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);
			}

			askedOnce = true;
			listenForGrant();
		}
		catch (e:Dynamic)
			trace('StorageUtil: could not ask for storage access ($e)');
	}

	static var listening:Bool = false;

	/** Shared storage is granted elsewhere, so the answer arrives as the game regaining focus. */
	static function listenForGrant():Void
	{
		if (listening) return;

		listening = true;
		flixel.FlxG.signals.focusGained.add(function()
		{
			if (usingSharedStorage) return;
			refresh();
		});
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
