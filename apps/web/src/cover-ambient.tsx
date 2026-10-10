import {useRef} from 'react';
import {useVisualVisibility} from './visual-lifecycle';

/** The image is filtered once; only its oversized wrapper drifts. */
export function CoverAmbient({artwork,active,playing,motion,blur}:{artwork:string|undefined;active:boolean;playing:boolean;motion:boolean;blur:boolean}){
 const element=useRef<HTMLDivElement>(null),visible=useVisualVisibility(element,active&&blur&&!!artwork);
 return <div ref={element} className="np-backdrop" aria-hidden="true" data-ambient-moving={visible&&playing&&motion} data-visual-visible={visible}>{blur&&artwork&&<div className="np-backdrop-drift"><div className="np-backdrop-image" style={artwork?{backgroundImage:`url(${JSON.stringify(artwork)})`}:undefined}/></div>}</div>;
}
