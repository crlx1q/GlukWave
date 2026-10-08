import type { Equalizer } from './types';

export const EQ_FREQUENCIES = [31,62,125,250,500,1000,2000,4000,8000,16000] as const;
export const EQ_PRESETS = [
  {id:'flat',label:'Flat',bands:[0,0,0,0,0,0,0,0,0,0],preamp:0},
  {id:'warm',label:'Warm',bands:[3,3,2,1,0,0,-1,-1,-2,-2],preamp:-3},
  {id:'vocal',label:'Vocal',bands:[-3,-2,-1,0,2,3,3,2,0,-1],preamp:-3},
  {id:'bass',label:'Bass',bands:[5,4,3,1,0,0,0,0,-1,-1],preamp:-5},
  {id:'bright',label:'Bright',bands:[-2,-1,0,0,0,1,2,3,3,2],preamp:-3},
] as const;

export type AudioGraph = {context:AudioContext;source:MediaElementAudioSourceNode;preamp:GainNode;bands:BiquadFilterNode[];limiter:DynamicsCompressorNode;analyser:AnalyserNode;data:Uint8Array<ArrayBuffer>};

/** Shared by playback and the offline acoustic verification. */
export function createEqualizer(context:BaseAudioContext, input:AudioNode) {
  const preamp=context.createGain();input.connect(preamp);
  let previous:AudioNode=preamp;
  const bands=EQ_FREQUENCIES.map(frequency=>{const filter=context.createBiquadFilter();filter.type='peaking';filter.frequency.value=Math.min(frequency,context.sampleRate*.45);filter.Q.value=Math.SQRT2;previous.connect(filter);previous=filter;return filter;});
  return {preamp,bands,output:previous};
}

export function configureEqualizer(graph:Pick<AudioGraph,'context'|'preamp'|'bands'>,settings:Equalizer) {
  const at=graph.context.currentTime;
  const smooth=(parameter:AudioParam,value:number)=>{parameter.cancelScheduledValues(at);parameter.setTargetAtTime(value,at,.025);};
  smooth(graph.preamp.gain,settings.enabled?10**(settings.preamp/20):1);
  graph.bands.forEach((band,index)=>smooth(band.gain,settings.enabled?settings.bands[index]||0:0));
}

export function createAudioGraph(context:AudioContext,audio:HTMLAudioElement):AudioGraph {
  const source=context.createMediaElementSource(audio),equalizer=createEqualizer(context,source),limiter=context.createDynamicsCompressor(),analyser=context.createAnalyser();
  // A final peak limiter protects custom boosts; presets include their own headroom.
  limiter.threshold.value=-1;limiter.knee.value=0;limiter.ratio.value=20;limiter.attack.value=.003;limiter.release.value=.15;
  analyser.fftSize=512;equalizer.output.connect(limiter);limiter.connect(analyser);analyser.connect(context.destination);
  return {context,source,preamp:equalizer.preamp,bands:equalizer.bands,limiter,analyser,data:new Uint8Array(512)};
}
