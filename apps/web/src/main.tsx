import { createRoot } from 'react-dom/client';
import { App } from './App';
import { LocaleProvider } from './locale';
import { Landing } from './landing';
import './styles.css';
import './experience.css';
import './v6.css';
import './v7.css';
import './connect-refinement.css';
import './ecosystem.css';
import './motion-controls.css';
import './parity.css';
import {installDiagnostics} from './diagnostics';
installDiagnostics();
const params=new URLSearchParams(location.search),legacyHash=['home','search','library','sources','rooms','lofi','downloads','settings','profile','admin'].includes(location.hash.slice(1).split('?')[0]),appQuery=['qr','native','secret','reset','invite','room','roomId','listen','jam','error','verified','signedIn','billing','track','connected','integration_error','emailConfirm'].some(key=>params.has(key));
const app=(location.pathname==='/app'||location.pathname.startsWith('/app/'))||legacyHash||appQuery;
createRoot(document.getElementById('root')!).render(<LocaleProvider>{app?<App/>:<Landing/>}</LocaleProvider>);

