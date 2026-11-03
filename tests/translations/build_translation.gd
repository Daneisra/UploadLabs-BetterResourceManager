extends SceneTree

# Compiles translations/BetterResourceManager.csv (key,<locale>...) into one
# OptimizedTranslation per locale.


func _initialize() -> void:
    var csv := FileAccess.open("res://BetterResourceManager.csv", FileAccess.READ)
    if csv == null:
        printerr("BRM TRANSLATION BUILD FAIL: missing CSV")
        quit(1)
        return
    var header := csv.get_csv_line()
    if header.size() < 2 or header[0] != "key":
        printerr("BRM TRANSLATION BUILD FAIL: invalid header")
        quit(1)
        return

    var sources: Array[Translation] = []
    for column in range(1, header.size()):
        var source := Translation.new()
        source.locale = header[column]
        sources.append(source)

    var seen: Dictionary = {}
    while csv.get_position() < csv.get_length():
        var row := csv.get_csv_line()
        if row.size() == 1 and row[0].is_empty():
            continue
        if row.size() != header.size() or row[0].is_empty() or seen.has(row[0]):
            printerr("BRM TRANSLATION BUILD FAIL: malformed or duplicate key %s" % row[0])
            quit(1)
            return
        for column in range(1, header.size()):
            sources[column - 1].add_message(row[0], row[column])
        seen[row[0]] = true
    csv.close()

    for source in sources:
        var compiled := OptimizedTranslation.new()
        compiled.generate(source)
        var path := "res://BetterResourceManager.%s.translation" % source.locale
        var result := ResourceSaver.save(compiled, path)
        if result != OK:
            printerr("BRM TRANSLATION BUILD FAIL: save %s returned %d" % [path, result])
            quit(1)
            return
    print("BRM TRANSLATION BUILD: %d messages x %d locales compiled" % [seen.size(), sources.size()])
    quit(0)
