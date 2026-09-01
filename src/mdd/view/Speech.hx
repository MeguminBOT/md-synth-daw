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
		words.put("preference.keeping", "Saving on its own");

		words.put("keeping.never", "Never");
		words.put("keeping.one", "Every minute");
		words.put("keeping.five", "Every 5 minutes");
		words.put("keeping.ten", "Every 10 minutes");

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
		words.put("view.tracker", "Tracker");
		words.put("view.arrangement", "Arrangement");
		words.put("view.mixer", "Mixer");
		words.put("view.warnings", "Warnings");

		words.put("scale.chromatic", "Chromatic");
		words.put("scale.major", "Major");
		words.put("scale.minor", "Natural minor");
		words.put("scale.harmonic", "Harmonic minor");
		words.put("scale.dorian", "Dorian");
		words.put("scale.mixolydian", "Mixolydian");
		words.put("scale.pentatonic", "Pentatonic");
		words.put("scale.minorPentatonic", "Minor pentatonic");
		words.put("scale.blues", "Blues");

		words.put("update.found", "There is a newer version");
		words.put("update.running", "Running");
		words.put("update.offered", "Available");
		words.put("update.consent", "Nothing is downloaded until asked for.");
		words.put("update.take", "Download it");
		words.put("update.later", "Not now");
		words.put("update.never", "Stop looking");
		words.put("file.update", "Look for an update");

		words.put("ready", "ready");

		return words;
	}
}
