extends SceneTree
var passed: bool = true
func _initialize() -> void:
 call_deferred("run_test")
func check(value: bool, detail: String) -> void:
 if not value:
  passed = false
  printerr("LARGE_GIFT_LAYOUT_FAIL ", detail)
func run_test() -> void:
 var previous_platform: String = OS.get_environment("LIVE_PLATFORM")
 OS.set_environment("LIVE_PLATFORM", "kwai")
 var hud: StadiumHUD = StadiumHUD.new()
 root.add_child(hud)
 for index: int in range(4):
  var rect: Rect2 = hud._showcase_panels[index].get_rect()
  check(rect.size.x == 492.0 and rect.end.y <= 1720.0, "large cards stay in broadcast safe area")
  check(hud._gift_images[index].size == Vector2(84.0,84.0), "larger gift image slot")
  check(hud._showcase_details[index].text.contains("DIAMANTES"), "Kwai shows mechanic bands without invented gift catalog")
  check(hud._gift_captions[index].get_theme_font_size("font_size") >= 24, "legible captions")
  for other: int in range(index):
   check(not rect.intersects(hud._showcase_panels[other].get_rect()), "cards do not overlap")
 var supporters: Array[Dictionary] = []
 for index: int in range(5):
  supporters.append({"display_name":"Fixture", "coins":10,"team":1})
 hud.update_leaderboard(supporters)
 check(hud._ranking_panel.get_rect().end.y < 1472.0, "top five stays above gift instructions")
 var instruction: Control = hud.frame.get_node("GiftTeamInstruction") as Control
 check(instruction.get_rect().end.y <= 1508.0, "instruction stays above large cards")
 hud.queue_free()
 await process_frame
 OS.set_environment("LIVE_PLATFORM", previous_platform)
 print("TEST_GIFT_SHOWCASE_LARGE_PASSED" if passed else "TEST_GIFT_SHOWCASE_LARGE_FAILED")
 quit(0 if passed else 1)
