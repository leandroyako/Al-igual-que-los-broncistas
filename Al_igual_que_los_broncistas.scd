s.options.numInputBusChannels_(2);
s.options.memSize_(8192*4);
(
s.waitForBoot({
	~inGroup = Group.new;
	~analysisGroup = Group.after(~inGroup);
	~recGroup = Group.after(~analysisGroup);
	~overdubGroup = Group.after(~recGroup);
	~fxGroup = Group.after(~overdubGroup);
	~encoderGroup = Group.after(~fxGroup);
	~decoderGroup = Group.after(~encoderGroup);

	~gtrBus = Bus.audio(s,1);
	~clBus = Bus.audio(s,1);
	~recBus = Bus.audio(s,1);
	~fxBus = Bus.audio(s,1);
	~encoderBus = Bus.audio(s,1);
	~ambiBus = Bus.audio(s, 4);

	b = Buffer.alloc(s, s.sampleRate*10, 1);

	SynthDef(\monoAudioIn, {
		| inBus = 0, amp = 1, outBus |

		var sig = SoundIn.ar(bus: inBus, mul: amp);
		OffsetOut.ar(outBus, sig);
	}).add;

	SynthDef(\onsets, {
		|inBus, outBus, threshold = 0.5, odtype = \rcomplex, reltime = 2, floor = 0.1, mingap = 10, id = 0|

		var sigIn, fft, onset;
		sigIn = In.ar(inBus);
		fft = FFT(LocalBuf(512), sigIn, wintype: 1);
		onset = Onsets.kr(fft, threshold, odtype, reltime, floor, mingap);
		SendReply.kr(onset, '/onsets', 1, id);
	}).add;

	SynthDef(\grainFreeze, {
		| inBus = 0, outBus = 0, amp = 0.4,
		trigRate = 60, grainDur = 0.5, grainPos = 0, rate = 1,
		delayTime = 0.5, attackTime = 0.5, decayTime = 0, sustainLevel = 1, releaseTime = 2, gate = 1 |

		var input, record, localBuf;
		var grainTrig, env, sig, distortTime;

		input = In.ar(inBus, 1);
		localBuf = LocalBuf.new(SampleRate.ir * 0.5, 1).clear;
		record = RecordBuf.ar(input, localBuf, loop: 0);

		grainTrig = Dust.ar(trigRate);
		sig = GrainBuf.ar(1, grainTrig, grainDur, localBuf, rate, grainPos);
		env = EnvGen.kr(Env.dadsr(delayTime, attackTime, decayTime, sustainLevel, releaseTime), gate, doneAction: 2);
		sig = sig * env;
		sig = Out.ar(outBus, sig * amp);
	}).add;

	SynthDef(\rec, {
		| inBus, buf |

		var src= In.ar(inBus);
		RecordBuf.ar(src, buf, loop: 1, doneAction:0);
	}).add;

	SynthDef(\play, {| outBus= 0, buf, dur= 1, rate = 1, lagTime |

		var tapehead= Phasor.ar(0, SampleDur.ir * Lag.kr(rate,lagTime), 0, dur);
		var src= BufRd.ar(1, buf, tapehead*SampleRate.ir, 1);
		Out.ar(outBus, src);
	}).add;

	SynthDef(\fx, {
		| outBus = 0, inBus = 0, bwr = 1, freq = 440, freqTime =1, res = 0.1, inputGain = 1, noiseLevel = 0, amp = 1, srcAmp = 0.1, cutoff = 880, srcAmpLagTime = 2,
		attackTime = 0.5, decayTime = 0, sustainLevel = 1, releaseTime = 5, gate = 1,
		thresh = 0.01, slopeBelow = 20, slopeAbove =  1, clampTime = 0.01, relaxTime = 0.1,
		cutoffLagTime = 0.1, gainLagTime = 0.1, bwrLagTime= 0.1, bwrCurve = 0,
		threshTime = 1, slopeBelowTime = 1, slopeAboveTime = 1 |

		var source, sig, env, pos;
		source = In.ar(inBus);
		env = EnvGen.kr(Env.adsr(attackTime, decayTime, sustainLevel, releaseTime), gate, doneAction: 2);
		sig = Mix.ar(Resonz.ar(source, VarLag.kr(freq, freqTime, 0), VarLag.kr(bwr, bwrLagTime, bwrCurve), amp));
		sig = DFM1.ar(sig, VarLag.kr(cutoff, cutoffLagTime, 0), res, VarLag.kr(inputGain, gainLagTime, 0), 0,  noiseLevel);
		sig = env * (sig + (source * VarLag.kr(srcAmp, srcAmpLagTime, 0)));
		sig = Compander.ar(sig, sig, VarLag.kr(thresh, threshTime, 0), VarLag.kr(slopeBelow, slopeBelowTime, 0), VarLag.kr(slopeAbove, slopeAboveTime, 0), clampTime, relaxTime,);
		Out.ar(outBus, sig);
	}).add;

	SynthDef(\bufplay, {
		| outBus = 0, outBus2 = 0, buf = 0, rate = 1, amp = 1, attackTime = 0.01, sustainLevel = 1, releaseTime = 1, pos = 0, gate = 1 |
		var sig, env;
		env = EnvGen.kr(Env.asr(attackTime, sustainLevel, releaseTime), gate, doneAction: 2);
		sig = PlayBuf.ar(1, buf, BufRateScale.ir(buf) * rate, doneAction: 2);
		sig = sig * amp;
		//	sig = Pan2.ar(sig, pos);
		Out.ar(outBus, sig * env);
		Out.ar(outBus2, sig * env);
	}).add;

	//Ambisonics

	SynthDef(\foaEncode, {
		| inBus, outBus, angle = 0, azim = 0 |

		var src, foa, encoder;
		// angle ---> top         = push to plane wave
		//          bottom    = omni-directional

		angle = Lag.kr(angle, 0.5);
		// azimuth -> hard left     = back
		//          centre     = centre
		//          hard right     = back
		azim = Lag.kr(azim, 0.2);

		encoder = FoaEncoderMatrix.newOmni;
		src = In.ar(inBus, 1);
		// Encode into our foa signal
		foa = FoaEncode.ar(src, encoder);
		foa = FoaTransform.ar(foa, 'push', angle, azim);
		// send out
		Out.ar(outBus, foa);
	}).add;

	~decoder = FoaDecoderKernel.newUHJ; // UHJ, a kernel decoder

	s.sync;

	SynthDef(\foaDecode, {
		| inBus |

		var foa, out, decoder;
		//decoder = FoaDecoderMatrix.newStereo;
		//decoder = FoaDecoderMatrix.newQuad;
		//decoder = FoaDecoderMatrix.newPanto(8);

		foa = In.ar(inBus, 4);
		out = FoaDecode.ar(foa, ~decoder);

		// send out
		Out.ar(0, out);
	}).add;

	s.sync;

	OSCdef(\cl, {|msg|
		"ONSET CL".postln;
		~recGroup.release;
		Synth(\grainFreeze, [\inBus, ~clBus, \outBus, ~recBus, \attackTime, 1, \releaseTime, 5, \rate, 1, \amp, 0.2], ~recGroup);
	}, '/onsets', argTemplate: [nil, 1, nil, nil]);

	OSCdef(\gtr, {|msg|
		"ONSET GTR".postln;
		~recGroup.release;
		Synth(\grainFreeze, [\inBus, ~gtrBus, \outBus, ~recBus, \attackTime, 1, \releaseTime, 5, \rate, 1, \amp, 0.2], ~recGroup);
	}, '/onsets', argTemplate: [nil, 2, nil, nil]);


	~path = "/home/yako/gtrPrep/PINZA/RESON";
	d = Dictionary.new;
	d.add(\samples ->
		PathName(~path).entries.collect({
			arg sf;
			Buffer.readChannel(s,sf.fullPath, channels: [0]); //Lee el canal izquierdo de todos los samples
		});
	);

	s.sync;

	MIDIClient.init;
	MIDIIn.connect(inport: 0, device: MIDIIn.findPort("Midi Through", "Midi Through Port-0"));
	//MIDIIn.connectAll;
	MIDIdef.cc(\playBuffer, {
		arg ...args;
		args.postln;
		~bufPlayer = Synth(\bufplay, [\buf, d[\samples].choose, \outBus, ~gtrBus, \outBus2, ~encoderBus], ~inGroup);
		~fxSynth.set(\slopeBelow, 0.1, \slopeBelowTime, 0.6);
	},
	16 //midiCC N° 16, chan omni
	);

	s.sync;

	~clIn = Synth(\monoAudioIn, [\inBus, 0, \outBus, ~clBus], ~inGroup);
	~gtrIn = Synth(\monoAudioIn, [\inBus, 1, \outBus, ~gtrBus], ~inGroup);

	~clOnset = Synth(\onsets, [\inBus, ~clBus, \id, 1], ~analysisGroup);
	~gtrOnset = Synth(\onsets, [\inBus, ~gtrBus, \id, 2], ~analysisGroup);
	//~gtrOnset.set(\threshold, 0.1);

	~overdubRec = Synth(\rec, [\inBus, ~recBus, \buf, b], ~overdubGroup);
	~overdubPlay = Synth(\play, [\outBus, ~fxBus, \buf, b, \dur, 10], ~overdubGroup, \addToTail);
	~overdubPlay.set(\rate, 1);

	~fxSynth = Synth("fx", [\inBus, ~fxBus, \outBus, ~encoderBus, \bwr, 0.1, \freq, Array.fill(10, {|i| i+1 * [220, 330] }), \amp, 1, \inputGain, 1, \res, 0.1, \noiseLevel, 0.001, \srcAmp, 0.1, \cutoff, 18000], ~fxGroup);

	~fxSynth.set(\inputGain, 1, \gainLagTime, 1, \noiseLevel, 0, \bwr, 0.01, \bwrLagTime, 15, \cutoff, 20000, \cutoffLagTime, 4);

	~fxSynth.set(\thresh, 0.4, \threshTime, 2, \slopeBelow, 40, \slopeBelowTime, 0.1, \slopeAbove, 1, \slopeAboveTime, 2, \clampTime, 0.001, \relaxTime, 0.1);

	//Ambisonics
	~decoderSynth = Synth.new(\foaDecode, [\inBus, ~ambiBus], ~decoderGroup);

	~encoderSynth = Synth.new(\foaEncode, [\inBus, ~encoderBus, \outBus, ~ambiBus], ~encoderGroup);

	"LISTO".postln;
});
)

//CONTROL
MIDIIn.doControlAction(1000, chan: 1, num: 16, val: 1); //Simula pedal midi
~fxSynth.release(0.3);

//~fxSynth.set(\thresh, 0.4, \threshTime, 2, \slopeBelow, 0.1, \slopeBelowTime, 0.6)
~fxSynth.set(\inputGain, 10, \gainLagTime, 15);
~fxSynth.set(\bwr, 0.1, \bwrLagTime, 2);
~fxSynth.set(\srcAmp, 0.001, \srcAmpLagTime, 5)
~fxSynth.set(\bwr, 0.001, \bwrLagTime, 15);

~fxSynth = Synth("fx", [\inBus, ~fxBus, \outBus, ~encoderBus, \bwr, 0.1, \freq, Array.fill(10, {|i| i+1 * [220, 330] }), \amp, 1, \inputGain, 1, \res, 0.1, \noiseLevel, 0.001, \srcAmp, 0.1, \cutoff, 18000], ~fxGroup);