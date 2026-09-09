package mobile.backend;

#if android
import android.content.Context;
#end
import haxe.io.Path;
import openfl.utils.Assets;

/**
 * Where the game keeps its writable files on a phone.
 *
 * Android hands every app a private folder under `Android/data/<package>/files`,
 * and `Main` makes that the working directory on startup, so the rest of Psych's
 * relative paths (`mods/`, `modsList.txt`, `crash/`, saves) keep working untouched.
 * Using that folder instead of the shared storage root is what keeps the port off
 * the `WRITE_EXTERNAL_STORAGE`/`MANAGE_EXTERNAL_STORAGE` treadmill: no runtime
 * permission prompt, and nothing to break on newer Android versions.
 */
class StorageUtil
{
	/** Writable root, with a trailing slash. Matches the working directory `Main` sets. */
	public static function getStorageDirectory():String
	{
		#if android
		return Path.addTrailingSlash(Context.getExternalFilesDir());
		#elseif ios
		return Path.addTrailingSlash(lime.system.System.applicationStorageDirectory);
		#else
		return Path.addTrailingSlash(Sys.getCwd());
		#end
	}

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
