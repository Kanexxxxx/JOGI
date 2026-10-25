extends SceneTree
var passed: bool = true
func _initialize() -> void:
 call_deferred("run_test")
func check(value: bool, detail: String) -> void:
 if not value:
  passed=false
  printerr("CLOCK_RECOVERY_FAIL ",detail)
func run_test() -> void:
 var race: StadiumRace = load("res://scenes/main/stadium_race.tscn").instantiate() as StadiumRace
 root.add_child(race)
 race.set_process(false)
 race.set_physics_process(false)
 var p: RacePersistence = RacePersistence.new()
 root.add_child(p)
 var store: RaceSessionStore = RaceSessionStore.new("local", RaceSessionStore.TEST_DIRECTORY_PREFIX+"clock_%d"%OS.get_process_id())
 check(p.setup(race,race.audience,race.event_bus,"local",store),"initial state valid")
 p.set_process(false)
 race.start_race_immediately()
 for runner: CandidateRunner in race.runners:
  runner.set_physics_process(false)
 race.runners[0].progress_m=7001.0
 race.runners[1].progress_m=7000.0
 # Values from the incident: cumulative addition used to exceed duration by ulps.
 race.race_elapsed_time=582.249999999799
 race.match_time_remaining=17.7500000002178
 var steps: int = 0
 while race.current_state==RaceMain.RaceState.RACING and steps<2000:
  race._physics_process(1.0/60.0)
  steps+=1
 check(race.race_elapsed_time==race.match_duration and race.match_time_remaining==0.0,"exact complementary clocks at finish")
 check(p.flush_snapshot() and p.is_ready,"finish checkpoint passes strict validation")
 while race.current_round==1 and steps<5000:
  race._physics_process(1.0/60.0)
  steps+=1
 check(race.current_round==2,"podium advances to following round")
 check(p.flush_snapshot(),"new round checkpoint valid")
 race.set_race_paused(true)
 var timer: float = race.match_time_remaining
 race._telemetry_timer=RaceMain.TELEMETRY_INTERVAL
 race._physics_process(0.1)
 check(race._telemetry_timer==0.0 and race.match_time_remaining==timer,"paused race emits heartbeat without advancing clock")
 race.set_race_paused(false)
 check(not race.race_paused,"safe resume remains available")
 p.is_ready=false
 p.queue_free()
 race.queue_free()
 await process_frame
 print("TEST_CHECKPOINT_CLOCK_RECOVERY_PASSED" if passed else "TEST_CHECKPOINT_CLOCK_RECOVERY_FAILED")
 quit(0 if passed else 1)
