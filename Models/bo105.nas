# $Id$
# Melchior FRANZ, < mfranz # aon : at >

if (!contains(globals, "cprint")) {
	globals.cprint = func {};
}
optarg = aircraft.optarg;
makeNode = aircraft.makeNode;



sort = func(l) {
	while (1) {
		var n = 0;
		for (var i = 0; i < size(l) - 1; i += 1) {
			if (cmp(l[i], l[i + 1]) > 0) {
				var t = l[i + 1];
				l[i + 1] = l[i];
				l[i] = t;
				n += 1;
			}
		}
		if (!n) {
			return l;
		}
	}
}


# strobes ===========================================================
var strobe_switch = props.globals.getNode("controls/lighting/strobe", 1);
aircraft.light.new("sim/model/bo105/lighting/strobe-top", 0.05, 1.00, strobe_switch);
aircraft.light.new("sim/model/bo105/lighting/strobe-bottom", 0.05, 1.03, strobe_switch);

# beacons ===========================================================
var beacon_switch = props.globals.getNode("controls/lighting/beacon", 1);
aircraft.light.new("sim/model/bo105/lighting/beacon-top", 0.62, 0.62, beacon_switch);
aircraft.light.new("sim/model/bo105/lighting/beacon-bottom", 0.63, 0.63, beacon_switch);



# nav lights ========================================================
var nav_light_switch = props.globals.getNode("controls/lighting/nav-lights", 1);
var visibility = props.globals.getNode("environment/visibility-m", 1);
var sun_angle = props.globals.getNode("sim/time/sun-angle-rad", 1);
var nav_lights = props.globals.getNode("sim/model/bo105/lighting/nav-lights", 1);

nav_light_loop = func {
	if (nav_light_switch.getValue()) {
		nav_lights.setValue(visibility.getValue() < 5000 or sun_angle.getValue() > 1.4);
	} else {
		nav_lights.setValue(0);
	}
	settimer(nav_light_loop, 3);
}

settimer(nav_light_loop, 0);



# doors =============================================================
var active_door = 0;
var doors = [];

init_doors = func {
	foreach (d; props.globals.getNode("sim/model/bo105/doors").getChildren("door")) {
		append(doors, aircraft.door.new(d, 2.5));
	}
}
settimer(init_doors, 0);

next_door = func { select_door(active_door + 1) }

previous_door = func { select_door(active_door - 1) }

select_door = func {
	active_door = arg[0];
	if (active_door < 0) {
		active_door = size(doors) - 1;
	} elsif (active_door >= size(doors)) {
		active_door = 0;
	}
	gui.popupTip("Selecting " ~ doors[active_door].node.getNode("name").getValue());
}

toggle_door = func {
	doors[active_door].toggle();
}



# engines/rotor =====================================================
var state = props.globals.getNode("sim/model/bo105/state");
var rotor = props.globals.getNode("controls/engines/engine/magnetos");
var rotor_rpm = props.globals.getNode("rotors/main/rpm");
var torque = props.globals.getNode("rotors/main/torque", 1);
var collective = props.globals.getNode("controls/engines/engine/throttle");
var turbine = props.globals.getNode("sim/model/bo105/turbine-rpm-pct", 1);
var torque_pct = props.globals.getNode("sim/model/bo105/torque-pct", 1);


# 0 off
# 1 startup sound in progress
# 2 sound loop
# 3 shutdown sound in progress

engines = func {
	s = state.getValue();
	if (arg[0] == 1) {
		if (s == 0) {
			state.setValue(1);				# engines started
			settimer(func { rotor.setValue(1) }, 3);
			interpolate(turbine, 100, 25);
			settimer(func { state.setValue(2) }, 10.5);	# -> engines running
		}
	} else {
		if (s == 2) {
			rotor.setValue(0);				# engines stopped
			state.setValue(3);
			interpolate(turbine, 0, 18);
			settimer(func { state.setValue(0) }, 25);	# -> engines off
		}
	}
}



# torquemeter
var torque_val = 0;

set_torque = func {
	var f = 0.075;				# low pass coeff
	if (new_fdm) {
		var t = torque.getValue();
		if (t != nil) {
			torque_val = t * f + torque_val * (1 - f);
			torque_pct.setDoubleValue(torque_val / 105);
		}
	} else {
		# yes, it's only faked for now  :-)
		var r = rotor_rpm.getValue() / 442;		# rotor norm
		var n = r * (17 + (1 - collective.getValue()) * 94);
		torque_pct.setValue(torque_val = n * f + torque_val * (1 - f));
	}
}




# crash handler =====================================================
var load = nil;
crash = func {
	if (arg[0]) {
		# crash
		setprop("sim/model/bo105/tail-angle", 35);
		setprop("sim/model/bo105/shadow", 0);
		setprop("sim/model/bo105/doors/door[0]/position-norm", 0.2);
		setprop("sim/model/bo105/doors/door[1]/position-norm", 0.9);
		setprop("sim/model/bo105/doors/door[2]/position-norm", 0.2);
		setprop("sim/model/bo105/doors/door[3]/position-norm", 0.6);
		setprop("sim/model/bo105/doors/door[4]/position-norm", 0.1);
		setprop("sim/model/bo105/doors/door[5]/position-norm", 0.05);
		setprop("rotors/main/rpm", 0);
		setprop("rotors/main/blade1_flap", -60);
		setprop("rotors/main/blade2_flap", -50);
		setprop("rotors/main/blade3_flap", -40);
		setprop("rotors/main/blade4_flap", -30);
		setprop("rotors/main/blade1_incidence", -30);
		setprop("rotors/main/blade2_incidence", -20);
		setprop("rotors/main/blade3_incidence", -50);
		setprop("rotors/main/blade4_incidence", -55);
		setprop("rotors/tail/rpm", 0);
		strobe_switch.setValue(0);
		beacon_switch.setValue(0);
		nav_light_switch.setValue(0);
		rotor.setValue(0);
		turbine.setValue(0);
		torque_pct.setValue(torqueval = 0);
		state.setValue(0);
		var n = props.globals.getNode("models", 1);
		for (var i = 0; 42; i += 1) {
			if (n.getChild("model", i, 0) == nil) {
				n = n.getChild("model", i, 1);
				n.setValues({
					"path": "Models/Fauna/cow.ac",
					"longitude-deg": getprop("position/longitude-deg"),
					"latitude-deg": getprop("position/latitude-deg"),
					"elevation-ft": getprop("position/ground-elev-ft"),
					"heading-deg": getprop("orientation/heading-deg"),
					#"pitch-deg": getprop("orientation/pitch-deg"),
					#"roll-deg": getprop("orientation/roll-deg"),
				});
				load = n;
				break;
			}
		}
	} else {
		# uncrash (for replay)
		setprop("sim/model/bo105/tail-angle", 0);
		setprop("sim/model/bo105/shadow", 1);
		foreach (d; doors) {
			d.setpos(0);
		}
		setprop("rotors/tail/rpm", 2219);
		setprop("rotors/main/rpm", 442);
		for (i = 1; i < 5; i += 1) {
			setprop("rotors/main/blade" ~ i ~ "_flap", 0);
			setprop("rotors/main/blade" ~ i ~ "_incidence", 0);
		}
		strobe_switch.setValue(1);
		beacon_switch.setValue(1);
		rotor.setValue(1);
		turbine.setValue(100);
		state.setValue(2);
	}
}




# "manual" rotor animation for flight data recorder replay ============
var rotor_step = props.globals.getNode("sim/model/bo105/rotor-step-deg");
var blade1_pos = props.globals.getNode("rotors/main/blade1_pos", 1);
var blade2_pos = props.globals.getNode("rotors/main/blade2_pos", 1);
var blade3_pos = props.globals.getNode("rotors/main/blade3_pos", 1);
var blade4_pos = props.globals.getNode("rotors/main/blade4_pos", 1);
var rotorangle = 0;

rotoranim_loop = func {
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

init_rotoranim = func {
	if (rotor_step.getValue() >= 0.0) {
		settimer(rotoranim_loop, 0.1);
	}
}



# Red Cross emblem ==================================================
determine_emblem = func {
	# Use the appropriate internationally acknowleged protective Red Cross/Crescent
	# symbol, depending on the starting airport. (http://www.ifrc.org/ADDRESS/directory.asp)

	var C = 1;	# Red Cross
	var L = 2;	# Rec Crescent (opening left)
	var R = 3;	# Red Crescent (opening right)
	var Y = 4;	# Red Crystal
	var X = 5;	# StarOfLife

	var emblem = [
		["<none>",       "empty.rgb"],
		["Red Cross",    "Emblems/red-cross.rgb"],
		["Red Crescent", "Emblems/red-crescent-l.rgb"],
		["Red Crescent", "Emblems/red-crescent-r.rgb"],
		["Red Crystal",  "Emblems/red-crystal.rgb"],
		["Star of Life", "Emblems/star-of-life.rgb"],
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

	var apt = getprop("/sim/presets/airport-id");
	var country = nil;
	var maxlen = -1;

	foreach (var entry; icao) {
		if (substr(apt, 0, size(entry[0])) == entry[0]) {
			if (size(entry[0]) > maxlen) {
				maxlen = size(entry[0]);
				country = entry;
			}
		}
	}
	print(apt ~ "/" ~ country[2] ~ " >> " ~ emblem[country[1]][0]);
	return emblem[country[1]][1];
}



Variant = {
	new : func {
		var m = { parents : [Variant] };
		m.emblem_medevac = determine_emblem();
		m.emblem_military = getprop("sim/model/bo105/insignia");
		m.list = m.scan();
		m.index = getprop("sim/model/bo105/variant");
		if (m.index >= size(m.list)) {
			m.index = 0;
		}
		m.reset();
		return m;
	},
	next : func {
		me.index += 1;
		if (me.index >= size(me.list)) {
			me.index = 0;
		}
		me.reset();
	},
	previous : func {
		me.index -= 1;
		if (me.index < 0) {
			me.index = size(me.list) - 1;
		}
		me.reset();
	},
	scan : func {
		var dir = "Aircraft/bo105/Models/Variants";
		var lst = [];
		foreach (var f; directory(getprop("/sim/fg-root") ~ "/" ~ dir)) {
			if (substr(f, size(f) - 4) == ".xml") {
				append(lst, dir ~ "/" ~ f);
			}
		}
		return sort(lst);
	},
	reset : func {
		me.load(me.list[me.index]);
	},
	load : func(file) {
		fgcommand("loadxml", props.Node.new({"filename": file, "targetnode": "sim/model/bo105"}));
		var emblem = getprop("/sim/model/bo105/emblem");
		if (emblem == "$MED") {
			emblem = me.emblem_medevac;
		} elsif (emblem == "$MIL") {
			emblem = me.emblem_military;
		} elsif (emblem == "") {
			emblem = "empty.rgb";
		}
		setprop("sim/model/bo105/material/emblem/texture", emblem);

		if (weapons != nil) {
			weapons.disable();
			weapons = nil;
		}

		if (getprop("sim/model/bo105/missiles")) {
			weapons = HOT;
		} elsif (getprop("sim/model/bo105/miniguns")) {
			weapons = MG;
		}

		if (weapons != nil) {
			weapons.enable();
			recalc_ammo_loop();
		}
		setprop("/sim/model/bo105/variant", me.index);
	},
};




# weapons ===========================================================

# aircraft.weapon.new(
#	<property>,
#	<submodel-index>,
#	<capacity>,
#	<drop-weight>,		# dropped weight per shot round/missile
#	<base-weight>		# remaining empty weight
#	[, <submodel-factor>	# one reported submodel counts for how many items
#	[, <weight-prop>]]);	# where to put the calculated weight
weapon = {
	new : func(prop, ndx, cap, dropw, basew, fac = 1, wprop = nil) {
		m = { parents : [weapon] };
		m.node = makeNode(prop);
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

		if (wprop != nil) {
			m.weightN = makeNode(wprop);
		} else {
			m.weightN = m.node.getNode("weight-lb", 1);
		}
		return m;
	},
	enable  : func { me.fire(0); me.enabledN.setBoolValue(arg[0]); me.update(); me },

	setammo : func { me.sm_countN.setValue(arg[0] / me.ratio); me.update(); me },
	getammo : func { me.countN.getValue() },
	getweight:func { me.weightN.getValue() },

	reload  : func { me.fire(0); me.setammo(me.capacity); me },

	update  : func {
		if (me.enabledN.getValue()) {
			me.countN.setValue(me.sm_countN.getValue() * me.ratio);
			me.weightN.setValue(me.baseweight + me.countN.getValue() * me.dropweight);
		} else {
			me.countN.setValue(0);
			me.weightN.setValue(0);
		}
	},

	fire    : func(t) {
		me.triggerN.setBoolValue(t);
		if (t) {
			me._loop_();
		}
	},

	_loop_  : func {
		me.update();
		if (me.triggerN.getBoolValue() and me.enabledN.getValue() and me.countN.getValue()) {
			settimer(func { me._loop_() }, 1);
		}
	},
};


# "name", <ammo-desc>
weapon_system = {
	new : func(name, adesc) {
		m = { parents : [weapon_system] };
		m.name = name;
		m.ammunition_type = adesc;
		m.weapons = [];
		m.enabled = 0;
		me.select = 0;
		return m;
	},
	add      : func { append(me.weapons, arg[0]) },
	reload   : func { me.select = 0; foreach (w; me.weapons) { w.reload() } },
	fire     : func { foreach (w; me.weapons) { w.fire(arg[0]) } },
	getammo  : func { n = 0; foreach (w; me.weapons) { n += w.getammo() }; n },
	ammodesc : func { me.ammunition_type },
	disable  : func { me.enabled = 0; foreach (w; me.weapons) { w.enable(0); } },
	enable   : func {
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

init_weapons = func {
	MG = weapon_system.new("M134", "rounds (7.62 mm)");
	# propellant: 2.98 g + bullet: 9.75 g  ->  0.0127 kg
	# M134 minigun: 18.8 kg + M27 armament subsystem: ??  ->
	MG.add(weapon.new("sim/model/bo105/weapons/MG[0]", 0, 4000, 0.0127, 100, 10));
	MG.add(weapon.new("sim/model/bo105/weapons/MG[1]", 1, 4000, 0.0127, 100, 10));

	HOT = weapon_system.new("HOT", "missiles");
	# 24 kg; missile + tube: 32 kg
	HOT.add(weapon.new("sim/model/bo105/weapons/HOT[0]", 2, 1, 24, 20));
	HOT.add(weapon.new("sim/model/bo105/weapons/HOT[1]", 3, 1, 24, 20));
	HOT.add(weapon.new("sim/model/bo105/weapons/HOT[2]", 4, 1, 24, 20));
	HOT.add(weapon.new("sim/model/bo105/weapons/HOT[3]", 5, 1, 24, 20));
	HOT.add(weapon.new("sim/model/bo105/weapons/HOT[4]", 6, 1, 24, 20));
	HOT.add(weapon.new("sim/model/bo105/weapons/HOT[5]", 7, 1, 24, 20));
	HOT.fire = func {
		if (arg[0]) {
			if (me.select < size(me.weapons)) {
				wp = me.weapons[me.select];
				wp.fire(1);
				weight = wp.weightN.getValue();
				wp.weightN.setValue(weight + 300);	# shake the bo
				settimer(func { wp.weightN.setValue(weight) }, 0.3);
				me.select += 1;
			}
		}
	};
}


var TRIGGER = -1;
setlistener("controls/armament/trigger", func {
	if (weapons != nil) {
		var t = cmdarg().getBoolValue();
		if (t != TRIGGER) {
			weapons.fire(TRIGGER = t);
		}
	}
});


setlistener("controls/gear/brake-left", func {
	setprop("controls/armament/trigger", cmdarg().getBoolValue());
});


reload = func {
	if (weapons != nil) {
		weapons.reload();
	}
}



# dialogs ===========================================================
var dialog = nil;

showDialog = func {
	name = "bo105-config";
	if (dialog != nil) {
		fgcommand("dialog-close", props.Node.new({ "dialog-name" : name }));
		dialog = nil;
		return;
	}

	dialog = gui.Widget.new();
	dialog.set("layout", "vbox");
	dialog.set("name", name);
	dialog.set("x", -40);
	dialog.set("y", -40);

	# "window" titlebar
	titlebar = dialog.addChild("group");
	titlebar.set("layout", "hbox");
	titlebar.addChild("empty").set("stretch", 1);
	titlebar.addChild("text").set("label", "Bo105 configuration");
	titlebar.addChild("empty").set("stretch", 1);

	dialog.addChild("hrule").addChild("dummy");

	w = titlebar.addChild("button");
	w.set("pref-width", 16);
	w.set("pref-height", 16);
	w.set("legend", "");
	w.set("default", 1);
	w.set("keynum", 27);
	w.set("border", 1);
	w.prop().getNode("binding[0]/command", 1).setValue("nasal");
	w.prop().getNode("binding[0]/script", 1).setValue("bo105.dialog = nil");
	w.prop().getNode("binding[1]/command", 1).setValue("dialog-close");

	checkbox = func {
		group = dialog.addChild("group");
		group.set("layout", "hbox");
		group.addChild("empty").set("pref-width", 4);
		box = group.addChild("checkbox");
		group.addChild("empty").set("stretch", 1);

		box.set("halign", "left");
		box.set("label", arg[0]);
		box;
	}

	# doors
	foreach (d; doors) {
		w = checkbox(d.node.getNode("name").getValue());
		w.set("property", d.node.getNode("enabled").getPath());
		w.prop().getNode("binding[0]/command", 1).setValue("dialog-apply");
	}

	# lights
	w = checkbox("beacons");
	w.set("property", "controls/lighting/beacon");
	w.prop().getNode("binding[0]/command", 1).setValue("dialog-apply");

	w = checkbox("strobes");
	w.set("property", "controls/lighting/strobe");
	w.prop().getNode("binding[0]/command", 1).setValue("dialog-apply");

	# ammunition
	group = dialog.addChild("group");
	group.set("layout", "hbox");
	group.addChild("empty").set("pref-width", 4);

	w = group.addChild("button");
	w.set("halign", "left");
	w.set("legend", "Reload");
	w.set("pref-width", 64);
	w.set("pref-height", 24);
	w.prop().getNode("binding[0]/command", 1).setValue("nasal");
	w.prop().getNode("binding[0]/script", 1).setValue("bo105.reload()");

	w = group.addChild("text");
	w.set("halign", "left");
	w.set("label", "X");
	w.set("pref-width", 200);
	w.set("property", "sim/model/bo105/weapons/ammunition");
	w.set("live", 1);

	group.addChild("empty").set("stretch", 1);

	# finale
	dialog.addChild("empty").set("pref-height", "3");
	fgcommand("dialog-new", dialog.prop());
	recalc_ammo_loop();
	gui.showDialog(name);
}


var ammoN = props.globals.getNode("sim/model/bo105/weapons/ammunition", 1);

recalc_ammo_loop = func {
	if (weapons != nil) {
		ammoN.setValue(weapons.getammo() ~ " " ~ weapons.ammodesc());
	} else {
		ammoN.setValue("");
	}
	if (dialog != nil) {
		settimer(recalc_ammo_loop, 0.2);
	}
}



# view management ===================================================

var cockpit_view = nil;
setlistener("/sim/current-view/view-number", func { cockpit_view = (cmdarg().getValue() == 0) }, 1);

var managed_view = nil;
setlistener("/sim/model/bo105/managed-view", func { managed_view = cmdarg().getBoolValue() }, 1);

var headingN = props.globals.getNode("orientation/heading-deg");
var pitchN = props.globals.getNode("orientation/pitch-deg");
var rollN = props.globals.getNode("orientation/roll-deg");
var speedN = props.globals.getNode("velocities/airspeed-kt");


ViewAxis = {
	new : func(prop) {
		var m = { parents : [ViewAxis] };
		m.prop = props.globals.getNode(prop, 0);
		m.reset();
		return m;
	},
	reset : func {
		me.applied_offset = 0;
	},
	input : func {
		die("ViewAxis.input() is pure virtual");
	},
	apply : func {
		var v = me.prop.getValue() - me.applied_offset;
		me.applied_offset = me.input();
		me.prop.setDoubleValue(v + me.applied_offset);
	},
};


ViewManager = {
	new : func {
		var m = { parents : [ViewManager] };
		m.heading = ViewAxis.new("sim/current-view/goal-heading-offset-deg");
		m.pitch = ViewAxis.new("sim/current-view/goal-pitch-offset-deg");
		m.roll = ViewAxis.new("sim/current-view/goal-roll-offset-deg");

		m.heading.input = func { rollN.getValue() * -0.5 }
		m.roll.input = func { rollN.getValue() * -0.4 }
		m.pitch.input = func {
			var pitch = pitchN.getValue();
			var roll = rollN.getValue();
			var s = 1.0 - speedN.getValue() / 140;
			if (s < 0) {
				s = 0;
			}
			if (roll >= 0) {
				return pitch * s * -0.6 + roll * 0.1;
			} else {
				return pitch * s * -0.6 + roll * -0.3;
			}
		}

		m.reset();
		return m;
	},
	reset : func {
		me.heading.reset();
		me.pitch.reset();
		me.roll.reset();
	},
	apply : func {
		me.heading.apply();
		me.pitch.apply();
		me.roll.apply();
	},
};




# main() ============================================================

main_loop = func {
	set_torque();

	if (cockpit_view and managed_view) {
		view_manager.apply();
	}
	settimer(main_loop, 0);
}


var CRASHED = 0;
var variant = nil;
var view_manager = nil;
var new_fdm = nil;


# initialization
settimer(func {
	settimer(func {
		new_fdm = getprop("rotors/main/torque") != nil;
		cprint("32;1", new_fdm ? "new FDM" : "old FDM");
	}, 5);

	init_rotoranim();
	init_weapons();

	variant = Variant.new();
	view_manager = ViewManager.new();

	setlistener("/sim/signals/reinit", func {
		cprint("32;1", "reinit ", cmdarg().getValue());
		variant.reset();
		view_manager.reset();
		CRASHED = 0;

		if (load != nil) {
			load.getNode("load", 1);
			load.removeChildren("load");
			load = nil;
		}
	});

	setlistener("sim/crashed", func {
		cprint("31;1", "crashed ", cmdarg().getValue());
		if (cmdarg().getBoolValue()) {
			crash(CRASHED = 1);
		}
	});

	setlistener("/sim/freeze/replay-state", func {
		cprint("33;1", "replay ", cmdarg().getValue());
		if (CRASHED) {
			crash(!cmdarg().getBoolValue())
		}
	});

	# the attitude indicator needs pressure
	settimer(func { setprop("engines/engine/rpm", 3000) }, 8);

	main_loop();
}, 0);


