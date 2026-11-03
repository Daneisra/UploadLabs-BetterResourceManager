extends SceneTree

# Verifies every compiled translation against the CSV, and that each locale
# keeps the same printf placeholders as English (a missing %s would raise a
# formatting error in game).

const PLACEHOLDER := "%[sdf]"


func fail(message: String) -> void:
    printerr("BRM TRANSLATION FAIL: " + message)
    quit(1)


func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        fail("Expected the CSV path")
        return
    var csv := FileAccess.open(args[0], FileAccess.READ)
    if csv == null:
        fail("Cannot open CSV")
        return
    var header := csv.get_csv_line()
    if header.size() < 2 or header[0] != "key" or header[1] != "en":
        fail("Unexpected CSV header")
        return

    var translations: Array[Translation] = []
    for column in range(1, header.size()):
        var path := args[0].get_base_dir().path_join("BetterResourceManager.%s.translation" % header[column])
        var translation := ResourceLoader.load(path) as Translation
        if translation == null or translation.locale != header[column]:
            fail("Cannot load compiled translation for locale %s" % header[column])
            return
        translations.append(translation)

    var regex := RegEx.new()
    regex.compile(PLACEHOLDER)
    var seen: Dictionary = {}
    var mismatches := 0
    while csv.get_position() < csv.get_length():
        var row := csv.get_csv_line()
        if row.size() == 1 and row[0].is_empty():
            continue
        if row.size() != header.size() or row[0].is_empty() or seen.has(row[0]):
            fail("Malformed or duplicate CSV key")
            return
        var english_placeholders := _placeholders(regex, row[1])
        for column in range(1, header.size()):
            var compiled := str(translations[column - 1].get_message(row[0]))
            if compiled != row[column]:
                printerr("CSV/compiled mismatch: %s [%s]" % [row[0], header[column]])
                mismatches += 1
            if _placeholders(regex, row[column]) != english_placeholders:
                printerr("Placeholder mismatch: %s [%s]" % [row[0], header[column]])
                mismatches += 1
        seen[row[0]] = true
    csv.close()

    if mismatches > 0:
        fail("%d mismatches" % mismatches)
        return
    print("BRM TRANSLATION: %d messages x %d locales verified, 0 failures" % [seen.size(), translations.size()])
    quit(0)


func _placeholders(regex: RegEx, text: String) -> Array:
    var result: Array = []
    for match in regex.search_all(text):
        result.append(match.get_string())
    return result
