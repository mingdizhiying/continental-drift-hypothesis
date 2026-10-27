import {mkdir, writeFile} from 'node:fs/promises';
import {initial, advance, parseOath, setOath, applyAiTurn} from '../world.js';

const scenarios = [];
function frame(s) {
  return structuredClone({turn: s.turn, current: s.current, visited: s.visited, ended: s.ended,
    cities: s.cities, events: s.events, interactions: s.interactions ?? [], links: s.links ?? [],
    historyCount: s.history.length,
    historyTail: s.history.filter(h => !h.cities).slice(-5), ending: s.ending});
}
function scenario(name, ops) {
  let state = initial(); const frames = [frame(state)];
  for (const op of ops) {
    if (op.kind === 'oath') state = setOath(state, parseOath(op.text));
    else if (op.kind === 'patch') Object.assign(state.cities.find(c => c.id === op.city), op.values);
    else if (op.kind === 'ai') state = applyAiTurn(state, op.data, state);
    else state = advance(state, op.action);
    frames.push(frame(state));
  }
  scenarios.push({name, ops, frames});
}
const actionOps = action => Array.from({length:60}, () => ({kind:'action',action}));
for (const action of ['observe','farm','mediate','build','restore']) scenario(action, actionOps(action));
for (const text of ['城市位置不变','永不缺粮','永远和平','守护贸易繁荣','守护森林']) {
  scenario(text, [{kind:'oath',text}, ...actionOps('observe')]);
}
scenario('mixed-and-replacement', Array.from({length:60}, (_,i) => [
  ...(i % 5 === 0 ? [{kind:'oath',text:['守护森林','永不缺粮','永远和平'][i % 3]}] : []),
  {kind:'action',action:['farm','mediate','build','restore','observe'][i % 5]},
]).flat());
scenario('anchor-sleep-resume', [{kind:'oath',text:'城市位置不变'},
  {kind:'patch',city:'ember',values:{peace:0}}, {kind:'action',action:'observe'},
  {kind:'patch',city:'ember',values:{peace:60}}, {kind:'action',action:'observe'},
  ...Array.from({length:10},()=>({kind:'action',action:'observe'}))]);
scenario('boundaries-events', [{kind:'patch',city:'ember',values:{x:934,y:534,vx:9,vy:9,food:0,peace:0,trade:100}},
  ...Array.from({length:20},()=>({kind:'action',action:'build'}))]);
await mkdir(new URL('../godot/tests/', import.meta.url), {recursive:true});
await writeFile(new URL('../godot/tests/reference.json', import.meta.url), JSON.stringify(scenarios));
console.log(`Generated ${scenarios.length} reference scenarios, ${scenarios.reduce((n,s)=>n+s.ops.length,0)} operations.`);
