# Melchior FRANZ, < mfranz # aon : at >

print("\x1b[35m
 _____                                _              ____        _  ___  ____
| ____|   _ _ __ ___   ___ ___  _ __ | |_ ___ _ __  | __ )  ___ / |/ _ \| ___|
|  _|| | | | '__/ _ \ / __/ _ \| '_ \| __/ _ \ '__| |  _ \ / _ \| | | | |___ \
| |__| |_| | | | (_) | (_| (_) | |_) | ||  __/ |    | |_) | (_) | | |_| |___) |
|_____\__,_|_|  \___/ \___\___/| .__/ \__\___|_|    |____/ \___/|_|\___/|____/
                               |_|
\x1b[m");


if (!contains(globals, "cprint"))
	var cprint = func nil;

var devel = getprop("devel") or 0;

var sin = func(a) math.sin(a * math.pi / 180.0);
var cos = func(a) math.cos(a * math.pi / 180.0);
var pow = func(v, w) math.exp(math.ln(v) * w);
var npow = func(v, w) v ? math.exp(math.ln(abs(v)) * w) * (v < 0 ? -1 : 1) : 0;
var clamp = func(v, min = 0, max = 1) v < min ? min : v > max ? max : v;
var normatan = func(x) math.atan2(x, 1) * 2 / math.pi;
var max = func(a, b) a > b ? a : b;
var min = func(a, b) a < b ? a : b;



# timers ============================================================
aircraft.timer.new("/sim/time/hobbs/helicopter", nil).start();

# strobes ===========================================================
var strobe_switch = props.globals.getNode("controls/lighting/strobe", 1);
aircraft.light.new("sim/model/bo105/lighting/strobe-top", [0.05, 1.00], strobe_switch);
aircraft.light.new("sim/model/bo105/lighting/strobe-bottom", [0.05, 1.03], strobe_switch);

# beacons ===========================================================
var beacon_switch = props.globals.getNode("controls/lighting/beacon", 1);
aircraft.light.new("sim/model/bo105/lighting/beacon-top", [0.62, 0.62], beacon_switch);
aircraft.light.new("sim/model/bo105/lighting/beacon-bottom", [0.63, 0.63], beacon_switch);


# nav lights ========================================================
var nav_light_switch = props.globals.getNode("controls/lighting/nav-lights", 1);
var visibility = props.globals.getNode("environment/visibility-m", 1);
var sun_angle = props.globals.getNode("sim/time/sun-angle-rad", 1);
var nav_lights = props.globals.getNode("sim/model/bo105/lighting/nav-lights", 1);

var nav_light_loop = func {
	if (nav_light_switch.getValue())
		nav_lights.setValue(visibility.getValue() < 5000 or sun_angle.getValue() > 1.4);
	else
		nav_lights.setValue(0);

	settimer(nav_light_loop, 3);
}

nav_light_loop();



# doors =============================================================
var Doors = {
	new : func {
		var m = { parents : [Doors] };
		m.active = 0;
		m.list = [];
		foreach (var d; props.globals.getNode("sim/model/bo105/doors").getChildren("door"))
			append(m.list, aircraft.door.new(d, 2.5));
		return m;
	},
	next : func {
		me.select(me.active + 1);
	},
	previous : func {
		me.select(me.active - 1);
	},
	select : func(which) {
		me.active = which;
		if (me.active < 0)
			me.active = size(me.list) - 1;
		elsif (me.active >= size(me.list))
			me.active = 0;
		gui.popupTip("Selecting " ~ me.list[me.active].node.getNode("name").getValue());
	},
	toggle : func {
		me.list[me.active].toggle();
	},
	reset : func {
		foreach (var d; me.list)
			d.setpos(0);
	},
};



# engines/rotor =====================================================
var rotor_rpm = props.globals.getNode("rotors/main/rpm");
var torque = props.globals.getNode("rotors/gear/total-torque", 1);
var collective = props.globals.getNode("controls/engines/engine[0]/throttle");
var turbine = props.globals.getNode("sim/model/bo105/turbine-rpm-pct", 1);
var torque_pct = props.globals.getNode("sim/model/bo105/torque-pct", 1);
var target_rel_rpm = props.globals.getNode("controls/rotor/reltarget", 1);
var max_rel_torque = props.globals.getNode("controls/rotor/maxreltorque", 1);


var Engine = {
	new : func(n) {
		var m = { parents: [Engine] };
		m.in = props.globals.getNode("controls/engines", 1).getChild("engine", n, 1);
		m.out = props.globals.getNode("engines", 1).getChild("engine", n, 1);
		m.airtempN = props.globals.getNode("/environment/temperature-degc");

		# input
		m.ignitionN = props.initNode(m.in.getNode("ignition", 1), 0, "BOOL");
		m.starterN = props.initNode(m.in.getNode("starter", 1), 0, "BOOL");
		m.powerN = props.initNode(m.in.getNode("power", 1), 0);
		m.magnetoN = props.initNode(m.in.getNode("magnetos", 1), 1, "INT");

		# output
		m.runningN = props.initNode(m.out.getNode("running", 1), 0, "BOOL");
		m.n1_pctN = props.initNode(m.out.getNode("n1-pct", 1), 0);
		m.n2_pctN = props.initNode(m.out.getNode("n2-pct", 1), 0);
		m.n1N = props.initNode(m.out.getNode("n1-rpm", 1), 0);
		m.n2N = props.initNode(m.out.getNode("n2-rpm", 1), 0);
		m.totN = props.initNode(m.out.getNode("tot-degc", 1), m.airtempN.getValue());

		m.starterLP = aircraft.lowpass.new(3);
		m.n1LP = aircraft.lowpass.new(4);
		m.n2LP = aircraft.lowpass.new(4);
		setlistener("/sim/signals/reinit", func(n) n.getValue() or m.reset(), 1);
		m.timer = aircraft.timer.new("/sim/time/hobbs/turbines[" ~ n ~ "]", 10);
		m.running = 0;
		m.fuelflow = 0;
		m.n1 = -1;
		m.up = -1;
		return m;
	},
	reset : func {
		me.ignitionN.setBoolValue(0);
		me.starterN.setBoolValue(0);
		me.powerN.setDoubleValue(0);
		me.magnetoN.setIntValue(1);
		me.runningN.setBoolValue(me.running = 0);
		me.starterLP.set(0);
		me.n1LP.set(0);
		me.n2LP.set(0);
	},
	update : func(dt, trim = 0) {
		var starter = me.starterLP.filter(me.starterN.getValue() * 0.19);	# starter 15-20% N1max
		me.powerN.setValue(me.power = clamp(me.powerN.getValue()));
		var power = me.power * 0.97 + trim;					# 97% = N2% in flight position

		if (me.running)
			power += (1 - collective.getValue()) * 0.03;			# droop compensator
		if (power > 1.12)
			power = 1.12;							# overspeed restrictor

		if (!me.running) {
			if (me.n1 > 0.05 and power > 0.05 and me.ignitionN.getValue()) {
				me.runningN.setBoolValue(me.running = 1);
				me.timer.start();
			}

		} elsif (power < 0.05) {
			me.runningN.setBoolValue(me.running = 0);
			me.timer.stop();
			me.fuelflow = 0;

		} else {
			me.fuelflow = power;
		}

		var lastn1 = me.n1;
		me.n1 = me.n1LP.filter(max(me.fuelflow, starter));
		me.n2 = me.n2LP.filter(me.n1);
		me.up = me.n1 - lastn1;

		# temperature
		if (me.fuelflow > me.pos.idle)
			var target = 440 + (779 - 440) * (0.03 + me.fuelflow - me.pos.idle) / (me.pos.flight - me.pos.idle);
		else
			var target = 440 * (0.03 + me.fuelflow) / me.pos.idle;

		if (me.n1 < 0.4 and me.fuelflow - me.n1 > 0.001) {
			target += (me.fuelflow - me.n1) * 7000;
			if (target > 980)
				target = 980;
		}

		var airtemp = me.airtempN.getValue();
		if (target < airtemp)
			target = airtemp;

		var decay = (me.up > 0 ? 10 : me.n1 > 0.02 ? 0.01 : 0.001) * dt;
		me.totN.setValue((me.totN.getValue() + decay * target) / (1 + decay));

		# derived gauge values
		me.n1_pctN.setDoubleValue(me.n1 * 100);
		me.n2_pctN.setDoubleValue(me.n2 * 100);
		me.n1N.setDoubleValue(me.n1 * 50970);
		me.n2N.setDoubleValue(me.n2 * 33290);
	},
	setpower : func(v) {
		var target = (int((me.power + 0.15) * 3) + v) / 3;
		var time = abs(me.power - target) * 4;
		interpolate(me.powerN, target, time);
	},
	adjust_power : func(delta, mode = 0) {
		if (delta) {
			var power = me.powerN.getValue();
			if (me.power_min == nil) {
				if (delta > 0) {
					if (power < me.pos.idle) {
						me.power_min = me.pos.cutoff;
						me.power_max = me.pos.idle;
					} else {
						me.power_min = me.pos.idle;
						me.power_max = me.pos.flight;
					}
				} else {
					if (power > me.pos.idle) {
						me.power_max = me.pos.flight;
						me.power_min = me.pos.idle;
					} else {
						me.power_max = me.pos.idle;
						me.power_min = me.pos.cutoff;
					}
				}
			}
			me.powerN.setValue(power = clamp(power + delta, me.power_min, me.power_max));
			return power;
		} elsif (mode) {
			me.power_min = me.power_max = nil;
		}
	},
	pos : { cutoff: 0, idle: 0.63, flight: 1 },
};


var engines = {
	init : func {
		me.engine = [Engine.new(0), Engine.new(1)];
		me.trimN = props.initNode("/controls/engines/power-trim", 0);
		me.balanceN = props.initNode("/controls/engines/power-balance", 0);
	},
	update : func(dt) {
		# each starter button disables ignition switch of opposite engine
		if (me.engine[0].starterN.getValue())
			me.engine[1].ignitionN.setBoolValue(0);
		if (me.engine[1].starterN.getValue())
			me.engine[0].ignitionN.setBoolValue(0);

		# update engines
		var trim = me.trimN.getValue() * 0.1;
		var balance = me.balanceN.getValue() * 0.1;
		me.engine[0].update(dt, trim - balance);
		me.engine[1].update(dt, trim + balance);

		# set rotor
		var n2max = max(me.engine[0].n2, me.engine[1].n2);
		target_rel_rpm.setValue(n2max);
		max_rel_torque.setValue(n2max);

		# Warning Box Type K-DW02/01
		if (n2max > 0.67) { # 0.63?
			setprop("sim/sound/warn2600", n2max > 1.08);
			setprop("sim/sound/warn650", abs(me.engine[0].n2 - me.engine[1].n2) > 0.12
					or n2max > 0.75 and n2max < 0.95);
		} else {
			setprop("sim/sound/warn2600", 0);
			setprop("sim/sound/warn650", 0);
		}
	},
	adjust_power : func(delta, mode = 0) {
		if (!delta) {
			engines.engine[0].adjust_power(0, mode);
			engines.engine[1].adjust_power(0, mode);
		} else {
			var p = [0, 0];
			for (var i = 0; i < 2; i += 1)
				if (controls.engines[i].selected.getValue())
					p[i] = engines.engine[i].adjust_power(delta);
			gui.popupTip(sprintf("power lever %d%%", 100 * max(p[0], p[1])));
		}
	},
};



if (devel) {
	setlistener("/sim/signals/fdm-initialized", func {
		settimer(func {
			screen.property_display.x = 760;
			screen.property_display.y = 200;
			screen.property_display.format = "%.3g";
			screen.property_display.add(
				rotor_rpm,
				torque_pct,
				target_rel_rpm,
				max_rel_torque,
				"/controls/engines/power-trim",
				"/controls/engines/power-balance",
				"L",
				engines.engine[0].runningN,
				engines.engine[0].ignitionN,
				"/controls/engines/engine[0]/power",
				engines.engine[0].n1_pctN,
				engines.engine[0].n2_pctN,
				engines.engine[0].totN,
				#engines.engine[0].n1N,
				#engines.engine[0].n2N,
				"R",
				engines.engine[1].runningN,
				engines.engine[1].ignitionN,
				"/controls/engines/engine[1]/power",
				engines.engine[1].n1_pctN,
				engines.engine[1].n2_pctN,
				engines.engine[1].totN,
				#engines.engine[1].n1N,
				#engines.engine[1].n2N,
			);
		}, 1);
	});
}



# adjust power lever via vertical MMB drag
var mouse = { savex: nil, savey: nil };
setlistener("/sim/startup/xsize", func(n) mouse.centerx = int(n.getValue() / 2), 1);
setlistener("/sim/startup/ysize", func(n) mouse.centery = int(n.getValue() / 2), 1);
setlistener("/sim/mouse/hide-cursor", func(n) mouse.hide = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/x", func(n) mouse.x = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/y", func(n) mouse.y = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/mode", func(n) mouse.mode = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/button[1]", func(n) {
	mouse.mmb = n.getValue();
	if (mouse.mode)
		return;
	if (mouse.mmb) {
		engines.adjust_power(0, 1);
		mouse.savex = mouse.x;
		mouse.savey = mouse.y;
		gui.setCursor(mouse.centerx, mouse.centery, "none");
	} else {
		gui.setCursor(mouse.savex, mouse.savey, "pointer");
	}
}, 1);



mouse.update = func(dt) {
	if (mouse.mode or !mouse.mmb)
		return;

	if (var dy = -mouse.y + mouse.centery) {
		engines.adjust_power(dy * dt * 0.075);
		gui.setCursor(mouse.centerx, mouse.centery);
	}
}



var power = func(v) {
	if (controls.engines[0].selected.getValue())
		engines.engine[0].setpower(v);
	if (controls.engines[1].selected.getValue())
		engines.engine[1].setpower(v);
}


var startup = func {
	if (procedure.stage < 0) {
		procedure.step = 1;
		procedure.next();
	}
}


var shutdown = func {
	if (procedure.stage > 0) {
		procedure.step = -1;
		procedure.next();
	}
}


var procedure = {
	stage : -999,
	step : nil,
	next : func(delay = 0) {
		if (crashed)
			return;
		if (me.stage < 0 and me.step > 0 or me.stage > 0 and me.step < 0)
			me.stage = 0;

		settimer(func me.process(me.stage += me.step), delay);
	},
	process : func {
		# startup
		if (me.stage == 1) {
			cprint("", "1: press start button #1 -> spool up turbine #1 to N1 8.6--15%");
			setprop("/controls/rotor/brake", 0);
			engines.engine[0].ignitionN.setValue(1);
			engines.engine[0].starterN.setValue(1);
			me.next(4);

		} elsif (me.stage == 2) {
			cprint("", "2: move power lever #1 forward -> fuel injection");
			engines.engine[0].powerN.setValue(0.13);
			me.next(2.5);

		} elsif (me.stage == 3) {
			cprint("", "3: turbine #1 ignition (wait for EGT stabilization)");
			me.next(4.5);

		} elsif (me.stage == 4) {
			cprint("", "4: move power lever #1 to idle position -> engine #1 spools up to N1 63%");
			engines.engine[0].powerN.setValue(0.63);
			me.next(5);

		} elsif (me.stage == 5) {
			cprint("", "5: release start button #1\n");
			engines.engine[0].starterN.setValue(0);
			engines.engine[0].ignitionN.setValue(0);
			me.next(3);

		} elsif (me.stage == 6) {
			cprint("", "6: press start button #2 -> spool up turbine #2 to N1 8.6--15%");
			engines.engine[1].ignitionN.setValue(1);
			engines.engine[1].starterN.setValue(1);
			me.next(5);

		} elsif (me.stage == 7) {
			cprint("", "7: move power lever #2 forward -> fuel injection");
			engines.engine[1].powerN.setValue(0.13);
			me.next(2);

		} elsif (me.stage == 8) {
			cprint("", "8: turbine #2 ignition (wait for EGT stabilization)");
			me.next(5);

		} elsif (me.stage == 9) {
			cprint("", "9: move power lever #2 to idle position -> engine #2 spools up to N1 63%");
			engines.engine[1].powerN.setValue(0.63);
			me.next(8);

		} elsif (me.stage == 10) {
			cprint("", "10: release start button #2\n");
			engines.engine[1].starterN.setValue(0);
			engines.engine[1].ignitionN.setValue(0);
			me.next(1);

		} elsif (me.stage == 11) {
			cprint("", "11: move both power levers forward -> turbines spool up to 100%");
			engines.engine[0].powerN.setValue(1);
			engines.engine[1].powerN.setValue(1);

		# shutdown
		} elsif (me.stage == -1) {
			cprint("", "-1: power lever in idle position; cool engines");
			engines.engine[0].starterN.setValue(0);
			engines.engine[1].starterN.setValue(0);
			engines.engine[0].ignitionN.setValue(0);
			engines.engine[1].ignitionN.setValue(0);
			engines.engine[0].powerN.setValue(0.63);
			engines.engine[1].powerN.setValue(0.63);
			me.next(40);

		} elsif (me.stage == -2) {
			cprint("", "-2: engines shut down\n");
			engines.engine[0].powerN.setValue(0);
			engines.engine[1].powerN.setValue(0);
			me.next(40);

		} elsif (me.stage == -3) {
			cprint("", "-3: rotor brake\n");
			setprop("/controls/rotor/brake", 1);
		}
	},
};



# torquemeter
var torque_val = 0;
torque.setDoubleValue(0);

var update_torque = func(dt) {
	var f = dt / (0.2 + dt);
	torque_val = torque.getValue() * f + torque_val * (1 - f);
	torque_pct.setDoubleValue(torque_val / 5300);
}



# blade vibration absorber pendulum
var pendulum = props.globals.getNode("/sim/model/bo105/absorber-angle-deg", 1);
var update_absorber = func {
	pendulum.setDoubleValue(90 * clamp(abs(rotor_rpm.getValue()) / 90));
}



# sound =============================================================

# stall sound
var stall = props.globals.getNode("rotors/main/stall", 1);
var stall_filtered = props.globals.getNode("rotors/main/stall-filtered", 1);

var stall_val = 0;
stall.setDoubleValue(0);

var update_stall = func(dt) {
	var s = stall.getValue();
	if (s < stall_val) {
		var f = dt / (0.3 + dt);
		stall_val = s * f + stall_val * (1 - f);
	} else {
		stall_val = s;
	}
	var c = collective.getValue();
	stall_filtered.setDoubleValue(stall_val + 0.006 * (1 - c));
}



# skid slide sound
var Skid = {
	new : func(n) {
		var m = { parents : [Skid] };
		var soundN = props.globals.getNode("sim/model/bo105/sound", 1).getChild("slide", n, 1);
		var gearN = props.globals.getNode("gear", 1).getChild("gear", n, 1);

		m.compressionN = gearN.getNode("compression-norm", 1);
		m.rollspeedN = gearN.getNode("rollspeed-ms", 1);
		m.frictionN = gearN.getNode("ground-friction-factor", 1);
		m.wowN = gearN.getNode("wow", 1);
		m.volumeN = soundN.getNode("volume", 1);
		m.pitchN = soundN.getNode("pitch", 1);

		m.compressionN.setDoubleValue(0);
		m.rollspeedN.setDoubleValue(0);
		m.frictionN.setDoubleValue(0);
		m.volumeN.setDoubleValue(0);
		m.pitchN.setDoubleValue(0);
		m.wowN.setBoolValue(1);
		m.self = n;
		return m;
	},
	update : func {
		if (me.wowN.getValue() < 0.5)
			return me.volumeN.setDoubleValue(0);

		var rollspeed = abs(me.rollspeedN.getValue());
		me.pitchN.setDoubleValue(rollspeed * 0.6);

		var s = normatan(20 * rollspeed);
		var f = clamp((me.frictionN.getValue() - 0.5) * 2);
		var c = clamp(me.compressionN.getValue() * 2);
		var vol = s * f * c;
		me.volumeN.setDoubleValue(vol > 0.1 ? vol : 0);
		#if (!me.self) {
		#	cprint("33;1", sprintf("S=%0.3f  F=%0.3f  C=%0.3f  >>  %0.3f", s, f, c, s * f * c));
		#}
	},
};

var skids = [];
for (var i = 0; i < 4; i += 1)
	append(skids, Skid.new(i));

var update_slide = func {
	foreach (var s; skids)
		s.update();
}

var volume_factor = 1;
setlistener("sim/current-view/view-number", func {
	volume_factor = getprop("sim/current-view/internal");
}, 1);


var volume = props.globals.getNode("sim/model/bo105/sound/volume", 1);
var update_volume = func {
	var door_open = 0;
	foreach (var d; doors.list) {
		if (!d.enabledN.getValue() or d.positionN.getValue() > 0.001) {
			door_open = 1;
			break;
		}
	}
	volume.setDoubleValue(1 - (0.8 - 0.6 * door_open) * volume_factor);
}



# crash handler =====================================================
#var load = nil;
var crash = func {
	if (arg[0]) {
		# crash
		setprop("sim/model/bo105/tail-angle-deg", 35);
		setprop("sim/model/bo105/shadow", 0);
		setprop("sim/model/bo105/doors/door[0]/position-norm", 0.2);
		setprop("sim/model/bo105/doors/door[1]/position-norm", 0.9);
		setprop("sim/model/bo105/doors/door[2]/position-norm", 0.2);
		setprop("sim/model/bo105/doors/door[3]/position-norm", 0.6);
		setprop("sim/model/bo105/doors/door[4]/position-norm", 0.1);
		setprop("sim/model/bo105/doors/door[5]/position-norm", 0.05);
		setprop("rotors/main/rpm", 0);
		setprop("rotors/main/blade[0]/flap-deg", -60);
		setprop("rotors/main/blade[1]/flap-deg", -50);
		setprop("rotors/main/blade[2]/flap-deg", -40);
		setprop("rotors/main/blade[3]/flap-deg", -30);
		setprop("rotors/main/blade[0]/incidence-deg", -30);
		setprop("rotors/main/blade[1]/incidence-deg", -20);
		setprop("rotors/main/blade[2]/incidence-deg", -50);
		setprop("rotors/main/blade[3]/incidence-deg", -55);
		setprop("rotors/tail/rpm", 0);
		strobe_switch.setValue(0);
		beacon_switch.setValue(0);
		nav_light_switch.setValue(0);
		engines.engine[0].n2_pct.setValue(0);
		engines.engine[1].n2_pct.setValue(0);
		torque_pct.setValue(torque_val = 0);
		stall_filtered.setValue(stall_val = 0);

	} else {
		# uncrash (for replay)
		setprop("sim/model/bo105/tail-angle-deg", 0);
		setprop("sim/model/bo105/shadow", 1);
		doors.reset();
		setprop("rotors/tail/rpm", 2219);
		setprop("rotors/main/rpm", 442);
		for (i = 0; i < 4; i += 1) {
			setprop("rotors/main/blade[" ~ i ~ "]/flap-deg", 0);
			setprop("rotors/main/blade[" ~ i ~ "]/incidence-deg", 0);
		}
		strobe_switch.setValue(1);
		beacon_switch.setValue(1);
		engines.engine[0].n2_pct.setValue(100);
		engines.engine[1].n2_pct.setValue(100);
	}
}




# "manual" rotor animation for flight data recorder replay ============
var rotor_step = props.globals.getNode("sim/model/bo105/rotor-step-deg");
var blade1_pos = props.globals.getNode("rotors/main/blade[0]/position-deg", 1);
var blade2_pos = props.globals.getNode("rotors/main/blade[1]/position-deg", 1);
var blade3_pos = props.globals.getNode("rotors/main/blade[2]/position-deg", 1);
var blade4_pos = props.globals.getNode("rotors/main/blade[3]/position-deg", 1);
var rotorangle = 0;

var rotoranim_loop = func {
	i = rotor_step.getValue();
	if (i >= 0.0) {
		blade1_pos.setValue(rotorangle);
		blade2_pos.setValue(rotorangle + 90);
		blade3_pos.setValue(rotorangle + 180);
		blade4_pos.setValue(rotorangle + 270);
		rotorangle += i;
		settimer(rotoranim_loop, 0.1);
	}
}

var init_rotoranim = func {
	if (rotor_step.getValue() >= 0.0)
		settimer(rotoranim_loop, 0.1);
}



# Red Cross emblem ==================================================
var determine_emblem = func {
	# Use the appropriate internationally acknowleged protective Red Cross/Crescent/Crystal
	# symbol, depending on the starting airport. (http://www.ifrc.org/ADDRESS/directory.asp)

	var C = 1;	# Red Cross
	var L = 2;	# Red Crescent (opening left)
	var R = 3;	# Red Crescent (opening right)
	var Y = 4;	# Red Crystal
	var X = 5;	# StarOfLife

	var emblem = [
		["<none>",       "Textures/empty.png"],
		["Red Cross",    "Textures/Emblems/red-cross.png"],
		["Red Crescent", "Textures/Emblems/red-crescent-l.png"],
		["Red Crescent", "Textures/Emblems/red-crescent-r.png"],
		["Red Crystal",  "Textures/Emblems/red-crystal.png"],
		["Star of Life", "Textures/Emblems/star-of-life.png"],
	];

	var icao = [
		["",	C, "<default>"],
		["DA",	R, "Algeria"],
		["DT",	L, "Tunisia"],
		["GM",	R, "Morocco"],
		["GQ",	R, "Mauritania"],
		["HC",	R, "Somalia"],
		["HD",	R, "Djibouti"],
		["HE",	R, "Egypt"],
		["HL",	R, "Libyan Arab Jamahiriya"],
		["HS",	R, "Sudan"],
		["LL",	Y, "Israel"],
		["LO",	C, "Austria"],
		["LT",	L, "Turkey"],
		["LV",	R, "Palestine"],
		["OA",	R, "Afghanistan"],
		["OB",	R, "Bahrain"],
		["OE",	R, "Saudi Arabia"],
		["OI",	R, "Islamic Republic of Iran"],
		["OJ",	R, "Jordan"],
		["OK",	R, "Kuwait"],
		["OM",	R, "United Arab Emirates"],
		["OP",	L, "Pakistan"],
		["OR",	R, "Iraq"],
		["OS",	R, "Syrian Arab Republic"],
		["OT",	R, "Qatar"],
		["OY",	R, "Yemen"],
		["UA",	R, "Kazakhstan"],
		["UAF",	L, "Kyrgyzstan"],
		["UB",	L, "Azerbaidjan"],
		["UT",	L, "Uzbekistan"],
		["UTA",	L, "Turkmenistan"],
		["UTD",	R, "Tajikistan"],
		["VG",	R, "Bangladesh"],
		["WB",	R, "Malaysia"],
		["WBAK",R, "Brunei Darussalam"],
		["WBSB",R, "Brunei Darussalam"],
		["WM",	R, "Malaysia"],
	];

	var apt = airportinfo().id;
	var country = nil;
	var maxlen = -1;

	foreach (var entry; icao) {
		var len = size(entry[0]);
		if (substr(apt, 0, len) == entry[0]) {
			if (len > maxlen) {
				maxlen = len;
				country = entry;
			}
		}
	}
	printlog("info", "bo105: ", apt ~ "/" ~ country[2] ~ " >> " ~ emblem[country[1]][0]);
	return emblem[country[1]][1];
}



# weapons ===========================================================

# aircraft.weapon.new(
#	<property>,
#	<submodel-index>,
#	<capacity>,
#	<drop-weight>,		# dropped weight per shot round/missile
#	<base-weight>		# remaining empty weight
#	[, <submodel-factor>	# one reported submodel counts for how many items
#	[, <weight-prop>]]);	# where to put the calculated weight
var Weapon = {
	new : func(prop, ndx, cap, dropw, basew, fac = 1, wprop = nil) {
		m = { parents : [Weapon] };
		m.node = aircraft.makeNode(prop);
		m.enabledN = m.node.getNode("enabled", 1);
		m.enabledN.setBoolValue(0);

		m.triggerN = m.node.getNode("trigger", 1);
		m.triggerN.setBoolValue(0);

		m.countN = m.node.getNode("count", 1);
		m.countN.setIntValue(0);

		m.sm_countN = props.globals.getNode("ai/submodels/submodel[" ~ ndx ~ "]/count", 1);
		m.sm_countN.setValue(0);

		m.capacity = cap;
		m.dropweight = dropw * 2.2046226;	# kg2lbs
		m.baseweight = basew * 2.2046226;
		m.ratio = fac;

		if (wprop != nil)
			m.weightN = aircraft.makeNode(wprop);
		else
			m.weightN = m.node.getNode("weight-lb", 1);
		return m;
	},
	enable : func {
		me.fire(0);
		me.enabledN.setBoolValue(arg[0]);
		me.update();
		me;
	},
	setammo : func {
		me.sm_countN.setValue(arg[0] / me.ratio);
		me.update();
		me;
	},
	getammo : func {
		me.countN.getValue();
	},
	getweight : func {
		me.weightN.getValue();
	},
	reload : func {
		me.fire(0);
		me.setammo(me.capacity);
		me;
	},
	update : func {
		if (me.enabledN.getValue()) {
			me.countN.setValue(me.sm_countN.getValue() * me.ratio);
			me.weightN.setValue(me.baseweight + me.countN.getValue() * me.dropweight);
		} else {
			me.countN.setValue(0);
			me.weightN.setValue(0);
		}
	},
	fire : func(t) {
		me.triggerN.setBoolValue(t);
		if (t)
			me._loop_();
	},
	_loop_  : func {
		me.update();
		if (me.triggerN.getBoolValue() and me.enabledN.getValue() and me.countN.getValue())
			settimer(func me._loop_(), 1);
	},
};


# "name", <ammo-desc>
var WeaponSystem = {
	new : func(name, adesc) {
		m = { parents : [WeaponSystem] };
		m.name = name;
		m.ammunition_type = adesc;
		m.weapons = [];
		m.enabled = 0;
		m.select = 0;
		return m;
	},
	add : func {
		append(me.weapons, arg[0]);
	},
	reload : func {
		me.select = 0;
		foreach (w; me.weapons)
			w.reload();
	},
	fire : func {
		foreach (w; me.weapons)
			w.fire(arg[0]);
	},
	getammo : func {
		n = 0;
		foreach (w; me.weapons)
			n += w.getammo();
		return n;
	},
	ammodesc : func {
		me.ammunition_type;
	},
	disable : func {
		me.enabled = 0;
		foreach (w; me.weapons)
			w.enable(0);
	},
	enable : func {
		me.select = 0;
		foreach (w; me.weapons) {
			w.enable(1);
			w.reload();
		}
		me.enabled = 1;
	},
};


var weapons = nil;
var MG = nil;
var HOT = nil;
var TRIGGER = -1;

var init_weapons = func {
	MG = WeaponSystem.new("M134", "rounds (7.62 mm)");
	# propellant: 2.98 g + bullet: 9.75 g  ->  0.0127 kg
	# M134 minigun: 18.8 kg + M27 armament subsystem: ??  ->
	MG.add(Weapon.new("sim/model/bo105/weapons/MG[0]", 0, 4000, 0.0127, 100, 10));
	MG.add(Weapon.new("sim/model/bo105/weapons/MG[1]", 1, 4000, 0.0127, 100, 10));

	HOT = WeaponSystem.new("HOT", "missiles");
	# 24 kg; missile + tube: 32 kg
	HOT.add(Weapon.new("sim/model/bo105/weapons/HOT[0]", 2, 1, 24, 20));
	HOT.add(Weapon.new("sim/model/bo105/weapons/HOT[1]", 3, 1, 24, 20));
	HOT.add(Weapon.new("sim/model/bo105/weapons/HOT[2]", 4, 1, 24, 20));
	HOT.add(Weapon.new("sim/model/bo105/weapons/HOT[3]", 5, 1, 24, 20));
	HOT.add(Weapon.new("sim/model/bo105/weapons/HOT[4]", 6, 1, 24, 20));
	HOT.add(Weapon.new("sim/model/bo105/weapons/HOT[5]", 7, 1, 24, 20));

	HOT.fire = func(trigger) {
		if (!trigger or me.select >= size(me.weapons))
			return;

		wp = me.weapons[me.select];
		wp.fire(1);
		settimer(func wp.fire(0), 1.5);
		weight = wp.weightN.getValue();
		wp.weightN.setValue(weight + 300);	# shake the bo
		settimer(func wp.weightN.setValue(weight), 0.3);
		me.select += 1;
	}

	setlistener("/sim/model/bo105/weapons/impact/HOT", func(n) {
		var node = props.globals.getNode(n.getValue(), 1);
		var impact = geo.Coord.new().set_latlon(
				node.getNode("impact/latitude-deg").getValue(),
				node.getNode("impact/longitude-deg").getValue(),
				node.getNode("impact/elevation-m").getValue());

		geo.put_model("Aircraft/bo105/Models/hot.ac", impact,
		#geo.put_model("Models/fgfsdb/coolingtower.xml", impact,
				node.getNode("impact/heading-deg").getValue(),
				node.getNode("impact/pitch-deg").getValue(),
				node.getNode("impact/roll-deg").getValue());
		screen.log.write(sprintf("%.3f km",
				geo.aircraft_position().distance_to(impact) / 1000), 1, 0.9, 0.9);

		fgcommand("play-audio-sample", props.Node.new({
			path : getprop("/sim/fg-root") ~ "/Aircraft/bo105/Sounds",
			file : "HOT.wav",
			volume : 0.2,
		}));
	});

	#setlistener("/sim/model/bo105/weapons/impact/MG", func(n) {
	#	var node = props.globals.getNode(n.getValue(), 1);
	#	geo.put_model("Models/Airport/ils.xml",
	#			node.getNode("impact/latitude-deg").getValue(),
	#			node.getNode("impact/longitude-deg").getValue(),
	#			node.getNode("impact/elevation-m").getValue(),
	#			node.getNode("impact/heading-deg").getValue(),
	#			node.getNode("impact/pitch-deg").getValue(),
	#			node.getNode("impact/roll-deg").getValue());
	#});

	setlistener("controls/armament/trigger", func(n) {
		if (weapons != nil) {
			var t = n.getBoolValue();
			if (t != TRIGGER)
				weapons.fire(TRIGGER = t);
		}
	});

	controls.applyBrakes = func(v) {
		setprop("controls/armament/trigger", v);
	}
}


# called from Dialogs/config.xml
var get_ammunition = func {
	weapons != nil ? weapons.getammo() ~ " " ~ weapons.ammodesc() : "";
}


var reload = func {
	if (weapons != nil)
		weapons.reload();
}



# view management ===================================================

var elapsedN = props.globals.getNode("/sim/time/elapsed-sec", 1);
var flap_mode = 0;
var down_time = 0;
controls.flapsDown = func(v) {
	if (!flap_mode) {
		if (v < 0) {
			down_time = elapsedN.getValue();
			flap_mode = 1;
			dynamic_view.lookat(
					5,     # heading left
					-20,   # pitch up
					0,     # roll right
					0.2,   # right
					0.6,   # up
					0.85,  # back
					0.2,   # time
					55,    # field of view
			);
		} elsif (v > 0) {
			flap_mode = 2;
			aircraft.autotrim.start();
		}

	} else {
		if (flap_mode == 1) {
			if (elapsedN.getValue() < down_time + 0.2)
				return;

			dynamic_view.resume();
		} elsif (flap_mode == 2) {
			aircraft.autotrim.stop();
		}
		flap_mode = 0;
	}
}


# register function that may set me.heading_offset, me.pitch_offset, me.roll_offset,
# me.x_offset, me.y_offset, me.z_offset, and me.fov_offset
#
dynamic_view.register(func {
	var lowspeed = 1 - normatan(me.speedN.getValue() / 50);
	var r = sin(me.roll) * cos(me.pitch);

	me.heading_offset =						# heading change due to
		(me.roll < 0 ? -50 : -30) * r * abs(r);			#    roll left/right

	me.pitch_offset =						# pitch change due to
		(me.pitch < 0 ? -50 : -50) * sin(me.pitch) * lowspeed	#    pitch down/up
		+ 15 * sin(me.roll) * sin(me.roll);			#    roll

	me.roll_offset =						# roll change due to
		-15 * r * lowspeed;					#    roll
});




# main() ============================================================
var delta_time = props.globals.getNode("/sim/time/delta-sec", 1);
var adf_rotation = props.globals.getNode("/instrumentation/adf/rotation-deg", 1);
var hi_heading = props.globals.getNode("/instrumentation/heading-indicator/indicated-heading-deg", 1);

var main_loop = func {
	adf_rotation.setDoubleValue(hi_heading.getValue());

	var dt = delta_time.getValue();
	update_torque(dt);
	update_stall(dt);
	update_slide();
	update_volume();
	update_absorber();
	mouse.update(dt);
	engines.update(dt);
	settimer(main_loop, 0);
}


var crashed = 0;
var rc_emblem = determine_emblem();
var doors = Doors.new();
var config_dialog = gui.Dialog.new("/sim/gui/dialogs/bo105/config/dialog", "Aircraft/bo105/Dialogs/config.xml");


setlistener("/sim/model/livery/file", func {
	if (weapons != nil) {
		weapons.disable();
		weapons = nil;
	}

	if (getprop("/sim/model/bo105/missiles"))
		weapons = HOT;
	elsif (getprop("/sim/model/bo105/miniguns"))
		weapons = MG;

	if (weapons != nil)
		weapons.enable();

	var emblemN = props.globals.getNode("/sim/model/bo105/material/emblem/texture");
	var emblem = emblemN.getValue();
	if (emblem == "RED-CROSS")
		emblemN.setValue(emblem = rc_emblem);
	elsif (emblem == "INSIGNIA")
		emblemN.setValue(emblem = getprop("/sim/model/bo105/insignia"));
	if (substr(emblem, 0, 17) == "Textures/Emblems/")
		emblem = substr(emblem, 17);
	if (substr(emblem, -4) == ".png")
		emblem = substr(emblem, 0, size(emblem) - 4);
	setprop("sim/multiplay/generic/string[0]", emblem);
});


aircraft.livery.init("Aircraft/bo105/Models/Variants", "sim/model/bo105/name", "sim/model/bo105/index");


# initialization
setlistener("/sim/signals/fdm-initialized", func {
	gui.menuEnable("autopilot", 0);
	init_rotoranim();
	init_weapons();
	engines.init();

	collective.setDoubleValue(1);

	setlistener("/sim/signals/reinit", func(n) {
		n.getBoolValue() and return;
		cprint("32;1", "reinit");
		collective.setDoubleValue(1);
		aircraft.livery.rescan();
		crashed = 0;
	});

	setlistener("sim/crashed", func(n) {
		cprint("31;1", "crashed ", n.getValue());
		engines.engine[0].timer.stop();
		engines.engine[1].timer.stop();
		if (n.getBoolValue())
			crash(crashed = 1);
	});

	setlistener("/sim/freeze/replay-state", func(n) {
		cprint("33;1", n.getValue() ? "replay" : "pause");
		if (crashed)
			crash(!n.getBoolValue())
	});

	# the attitude indicator needs pressure
	settimer(func { setprop("engines/engine/rpm", 3000) }, 8);

	main_loop();
});


