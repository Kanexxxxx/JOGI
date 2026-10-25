extends SceneTree
var race: StadiumRace
var passed: bool = true
var seq: int = 0
func _initialize() -> void:
 call_deferred("run_test")
func check(value: bool, detail: String) -> void:
 if not value:
  passed=false
  printerr("GIFT_TEAM_FAIL ",detail)
func gift(team: int, tier: int, value: int = -1) -> Dictionary:
 seq+=1
 var names: Array[String] = ["Rosa", "Mini dino", "Trompete de Festa", "Calêndula"]
 var actions: Array[String] = ["gift_t1_turbo", "gift_t2_shield_or_obstacle", "gift_t3_attack", "gift_t4_super_rally"]
 return {"schema_version":"1.0","source":"tiktok","event_type":"gift","event_id":"gift_teams_fixture_%08d"%seq,"user":{"user_id":"fixture_%d"%team,"display_name":"Pessoa teste"},"payload":{"candidate_slot":team,"gift_tier":"T%d"%tier,"action_id":actions[tier-1],"unit_coin_value":([1,10,149,1000][tier-1] if value<0 else value),"coin_value":([1,10,149,1000][tier-1] if value<0 else value),"repeat_count":1,"gift_id":"fixture_%d"%tier,"gift_name":names[tier-1]}}
func capture(label: String) -> void:
 var directory: String = OS.get_environment("JOGI_GIFT_CAPTURE_DIR")
 if directory.is_empty() or DisplayServer.get_name()=="headless":
  return
 DirAccess.make_dir_recursive_absolute(directory)
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory.path_join(label+".png"))
func clear_effects() -> void:
 for runner: CandidateRunner in race.runners:
  runner.boost_timer=0.0
  runner.shield_timer=0.0
  runner.stumble_timer=0.0
 for item: Node in race._obstacles_root.get_children():
  race._obstacles_root.remove_child(item)
  item.queue_free()
func run_test() -> void:
 race=load("res://scenes/main/stadium_race.tscn").instantiate() as StadiumRace
 root.add_child(race)
 race.set_process(false)
 race.set_physics_process(false)
 race.event_bus.session_platform="tiktok"
 race.start_race_immediately()
 for runner: CandidateRunner in race.runners:
  runner.set_physics_process(false)
 race.stadium_hud.set_process(false)
 await capture("00-startup-real-gift-art")
 for index: int in range(4):
  check(race.stadium_hud._gift_images[index].visible and race.stadium_hud._gift_images[index].texture != null,"permanent gift art available at startup")
  check(not race.stadium_hud._showcase_details[index].text.contains("NÃO CONFIRMADO"),"real screenshot values shown")
 for team: int in [1,2]:
  for tier: int in [1,2,3,4]:
   clear_effects()
   race.stadium_hud._interaction_entries.clear()
   race.stadium_hud._interaction_pending.clear()
   var event: Dictionary = gift(team,tier)
   if tier==3:
    event["payload"]["target_slot"]=team # must never trust a conflicting supplied target
   check(race.event_bus.ingest_envelope(event),"gift accepted once")
   var own: CandidateRunner = race.runners[team-1]
   var rival: CandidateRunner = race.runners[2-team]
   if tier in [1,4]:
    check(own.boost_timer>0.0 and rival.boost_timer==0.0,"boost belongs exclusively to sender team")
   if tier==2:
    check(own.shield_timer>0.0 and rival.shield_timer==0.0 and own.boost_timer==0.0,"shield protects only sender team")
   if tier==3:
    var obstacles: Array[Node] = race._obstacles_root.get_children()
    check(not obstacles.is_empty() and int(obstacles[-1].get_meta("target_slot"))==3-team,"attack directed at rival even with conflicting target")
    if not obstacles.is_empty():
     (obstacles[-1] as Area3D).body_entered.emit(rival)
     check(rival.stumble_timer>0.0 and own.stumble_timer==0.0,"attack applies stumble to rival")
   race.stadium_hud._elapsed += 0.4
   race.stadium_hud._animate_interaction_cards()
   await capture("tier%d-team%d"%[tier,team])
   var counts: Dictionary = race.audience.get_session_counts()
   check(not race.event_bus.ingest_envelope(event) and counts==race.audience.get_session_counts(),"paid duplicate never reapplies or recounts")
 clear_effects()
 check(race.event_bus.ingest_envelope(gift(0,1)),"neutral gift acknowledged")
 check(race.runners[0].boost_timer==0.0 and race.runners[1].boost_timer==0.0,"neutral gift never selects a beneficiary")
 check(race.event_bus.ingest_envelope(gift(1,1,0)),"unknown value gift retained")
 check(race.runners[0].boost_timer==0.0,"unknown value never invents paid benefit")
 check(race.stadium_hud.frame.get_node("GiftTeamInstruction").visible,"team instruction always visible")
 race.queue_free()
 await process_frame
 print("TEST_TIKTOK_GIFT_TEAMS_PASSED" if passed else "TEST_TIKTOK_GIFT_TEAMS_FAILED")
 quit(0 if passed else 1)
