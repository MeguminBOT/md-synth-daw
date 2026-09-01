package mdd.view;

import mdd.ui.Words;

class Speech {
	public static function english(words:Words):Words {
		words.speak("en");

		words.put("preferences", "Preferences");
		words.put("preferences.close", "Escape to close");
		words.put("preference.theme", "Theme");
		words.put("preference.motion", "Motion");
		words.put("preference.language", "Language");
		words.put("preference.density", "Density");

		words.put("theme.midnight", "Midnight");
		words.put("theme.rack", "Rack");
		words.put("theme.slate", "Slate");

		words.put("motion.full", "Full");
		words.put("motion.reduced", "Reduced");
		words.put("motion.none", "None");

		words.put("density.close", "Close");
		words.put("density.usual", "Usual");
		words.put("density.roomy", "Roomy");

		words.put("en", "English");

		words.put("menu.file", "File");
		words.put("menu.edit", "Edit");
		words.put("menu.view", "View");

		words.put("file.open", "Open");
		words.put("file.save", "Save");
		words.put("file.saveAs", "Save as");
		words.put("file.vgm", "Export a vgm");
		words.put("file.wav", "Export a wav");
		words.put("file.midi", "Export a midi file");
		words.put("file.preferences", "Preferences");
		words.put("file.quit", "Quit");

		words.put("edit.undo", "Undo");
		words.put("edit.redo", "Redo");
		words.put("edit.play", "Play or pause");
		words.put("edit.stop", "Stop");

		words.put("view.roll", "Piano roll");
		words.put("view.arrangement", "Arrangement");
		words.put("view.mixer", "Mixer");
		words.put("view.warnings", "Warnings");

		words.put("ready", "ready");

		return words;
	}
}
