extends SceneTree
## Check that the voice which reads a language aloud (see Voice) is the plain
## voice of the wanted locale, among the voices as the computers list them:
## eSpeak NG on Linux (with its many variants, and the variant in the place of
## the region), and the system voices of macOS and Windows.

const VoiceScript := preload("res://scenes/voice/voice.gd")

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
    if not condition:
        print("FAIL ", message)
        _failures.append(message)


func _initialize() -> void:
    _run.call_deferred()


static func _voices(entries: Array) -> Array:
    var result := []
    for entry in entries:
        result.append({"language": entry[0], "name": entry[1], "id": entry[1]})
    return result


func _run() -> void:
    # NOTE (mristin):
    # As Godot lists the voices of Speech Dispatcher with eSpeak NG on Linux.
    var linux := _voices(
        [
            ["af_none", "Afrikaans"],
            ["de_Andrea", "German+Andrea"],
            ["de_none", "German"],
            ["en-029_none", "English (Caribbean)"],
            ["en-GB-X-RP_none", "English (Received Pronunciation)"],
            ["en-GB_none", "English (Great Britain)"],
            ["en-US_none", "English (America)"],
            ["es-419_none", "Spanish (Latin America)"],
            ["es_none", "Spanish (Spain)"],
            ["fr-BE_none", "French (Belgium)"],
            ["fr-FR_none", "French (France)"],
            ["hr_Andrea", "Croatian+Andrea"],
            ["hr_none", "Croatian"],
            ["pt-BR_none", "Portuguese (Brazil)"],
            ["pt_none", "Portuguese (Portugal)"],
            ["sq_none", "Albanian"],
            ["sr_none", "Serbian"],
        ]
    )
    var expected := {
        ["de", "de_DE"]: "German",
        ["en", "en_GB"]: "English (Great Britain)",
        ["es", "es_ES"]: "Spanish (Spain)",
        ["fr", "fr_FR"]: "French (France)",
        ["hr", "hr_HR"]: "Croatian",
        ["pt", "pt_PT"]: "Portuguese (Portugal)",
        ["sq", "sq_AL"]: "Albanian",
        ["ru", "ru_RU"]: "",
    }
    for key in expected:
        var said := VoiceScript.best_voice(linux, key[0], key[1])
        _check(said == expected[key], "linux %s: %s" % [key[0], said])

    # NOTE (mristin):
    # As Godot lists the system voices of macOS and Windows.
    var system := _voices(
        [
            ["en_US", "Samantha"],
            ["en_GB", "Daniel"],
            ["pt_BR", "Luciana"],
            ["pt_PT", "Joana"],
            ["hr_HR", "Lana"],
            ["es_MX", "Paulina"],
            ["es_ES", "Monica"],
        ]
    )
    expected = {
        ["en", "en_GB"]: "Daniel",
        ["pt", "pt_PT"]: "Joana",
        ["hr", "hr_HR"]: "Lana",
        ["es", "es_ES"]: "Monica",
        ["sq", "sq_AL"]: "",
    }
    for key in expected:
        var said := VoiceScript.best_voice(system, key[0], key[1])
        _check(said == expected[key], "system %s: %s" % [key[0], said])

    # NOTE (mristin):
    # Another region is better than nothing.
    var only_brazil := _voices([["pt_BR", "Luciana"]])
    _check(VoiceScript.best_voice(only_brazil, "pt", "pt_PT") == "Luciana", "only Brazil")

    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        print("RESULT: FAILED (%d)" % _failures.size())
        quit(1)
