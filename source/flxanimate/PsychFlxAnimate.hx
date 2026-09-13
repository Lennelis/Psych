package flxanimate;

import flixel.util.FlxDestroyUtil;
import flixel.system.FlxAssets.FlxGraphicAsset;
import flxanimate.frames.FlxAnimateFrames;
import flxanimate.data.AnimationData;
import flxanimate.FlxAnimate as OriginalFlxAnimate;

class PsychFlxAnimate extends OriginalFlxAnimate
{
	public function loadAtlasEx(img:FlxGraphicAsset, pathOrStr:String = null, myJson:Dynamic = null)
	{
		var animJson:AnimAtlas = null;
		if(myJson is String)
		{
			var trimmed:String = pathOrStr.trim();
			trimmed = trimmed.substr(trimmed.length - 5).toLowerCase();

			if(trimmed == '.json') myJson = File.getContent(myJson); //is a path
			animJson = cast haxe.Json.parse(_removeBOM(myJson));
		}
		else animJson = cast myJson;

		var isXml:Null<Bool> = null;
		var myData:Dynamic = pathOrStr;

		var trimmed:String = pathOrStr.trim();
		trimmed = trimmed.substr(trimmed.length - 5).toLowerCase();

		if(trimmed == '.json') //Path is json
		{
			myData = File.getContent(pathOrStr);
			isXml = false;
		}
		else if (trimmed.substr(1) == '.xml') //Path is xml
		{
			myData = File.getContent(pathOrStr);
			isXml = true;
		}
		myData = _removeBOM(myData);

		// Automatic if everything else fails
		switch(isXml)
		{
			case true:
				myData = Xml.parse(myData);
			case false:
				myData = haxe.Json.parse(myData);
			case null:
				try
				{
					myData = haxe.Json.parse(myData);
					isXml = false;
					//trace('JSON parsed successfully!');
				}
				catch(e)
				{
					myData = Xml.parse(myData);
					isXml = true;
					//trace('XML parsed successfully!');
				}
		}

		anim._loadAtlas(animJson);
		if(!isXml) frames = FlxAnimateFrames.fromSpriteMap(cast myData, img);
		else frames = FlxAnimateFrames.fromSparrow(cast myData, img);
		origin = anim.curInstance.symbol.transformationPoint;
	}

	/**
	 * Swaps the artwork inside a symbol for a different graphic.
	 *
	 * V-Slice's album roll is an Animate atlas whose album cover is a placeholder symbol,
	 * white with a blue smear, replaced at runtime with whichever album the song belongs
	 * to. Its `FunkinSprite.replaceSymbolGraphic` does that through its own fork of
	 * flxanimate; the version Psych carries has no such call, so this is it.
	 *
	 * A limb in an atlas is drawn by looking its `bitmap` name up in the sprite's frame
	 * collection, so all this does is put a frame for the new graphic into that
	 * collection and point every limb inside the symbol at it. The art has to be the size
	 * the placeholder was drawn at - which the album covers are, 262 square - since
	 * nothing here rescales it.
	 */
	public function replaceSymbolGraphic(symbolName:String, graphic:flixel.graphics.FlxGraphic):Void
	{
		if (anim == null || anim.symbolDictionary == null || frames == null) return;

		var symbol = anim.symbolDictionary.get(symbolName);
		if (symbol == null)
		{
			trace('PsychFlxAnimate: no symbol called "$symbolName" to replace');
			return;
		}

		var frameName:String = 'psychReplaced::$symbolName';

		if (graphic != null && !frames.exists(frameName))
		{
			var frame = graphic.imageFrame.frame.copyTo();
			frame.name = frameName;
			frames.pushFrame(frame);
		}

		for (layer in symbol.timeline.getList())
		{
			@:privateAccess
			var keyFrames = layer._keyframes;
			if (keyFrames == null) continue;

			for (keyFrame in keyFrames)
			{
				if (keyFrame == null) continue;

				for (element in keyFrame.getList())
					if (element != null && element.bitmap != null) element.bitmap = frameName;
			}
		}
	}

	override function draw()
	{
		if(anim.curInstance == null || anim.curSymbol == null) return;
		super.draw();
	}

	override function destroy()
	{
		try
		{
			super.destroy();
		}
		catch(e:haxe.Exception)
		{
			anim.curInstance = FlxDestroyUtil.destroy(anim.curInstance);
			anim.stageInstance = FlxDestroyUtil.destroy(anim.stageInstance);
			//anim.metadata = FlxDestroyUtil.destroy(anim.metadata);
			anim.metadata.destroy();
			anim.symbolDictionary = null;
		}
	}

	function _removeBOM(str:String) //Removes BOM byte order indicator
	{
		if (str.charCodeAt(0) == 0xFEFF) str = str.substr(1); //myData = myData.substr(2);
		return str;
	}

	public function pauseAnimation()
	{
		if(anim.curInstance == null || anim.curSymbol == null) return;
		anim.pause();
	}
	public function resumeAnimation()
	{
		if(anim.curInstance == null || anim.curSymbol == null) return;
		anim.play();
	}
}