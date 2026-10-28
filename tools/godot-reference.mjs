import {mkdir, writeFile} from 'node:fs/promises';
import {initial, advance, parseOath, setOath, applyAiTurn} from './web-baseline/world.js';

const scenarios = [];
function frame(s) {
  return structuredClone({turn:s.turn,current:s.current,visited:s.visited,ended:s.ended,
    cities:s.cities,events:s.events,interactions:s.interactions??[],links:s.links??[],
    seed:s.seed,truces:s.truces,lastAction:s.lastAction??null,historyCount:s.history.length,
    historyTail:s.history.filter(h=>!h.cities).slice(-5),ending:s.ending});
}
function scenario(name, desiredOps, seed=123) {
  let state=initial(seed), lastBefore=state; const frames=[frame(state)], ops=[];
  for(const source of desiredOps) {
    const op=structuredClone(source);
    try {
      if(op.kind==='oath') state=setOath(state,parseOath(op.text));
      else if(op.kind==='patch') Object.assign(state.cities.find(c=>c.id===op.city),op.values);
      else if(op.kind==='worldPatch') Object.assign(state,structuredClone(op.values));
      else if(op.kind==='ai') state=applyAiTurn(state,op.data,lastBefore);
      else {lastBefore=state;state=advance(state,op.action,op.targetId);}
    } catch(error) {op.expectedError=error.message;}
    ops.push(op);frames.push(frame(state));
  }
  while(!state.ended && state.turn<60) {
    lastBefore=state;state=advance(state,'observe');ops.push({kind:'action',action:'observe'});frames.push(frame(state));
  }
  scenarios.push({name,seed,ops,frames});
}
const play=action=>Array.from({length:60},()=>({kind:'action',action}));
for(const action of ['observe','farm','investigate','build','restore','forest','forge','reveal']) scenario(action,play(action));
for(const text of ['城市位置不变','永不缺粮','永远和平','守护贸易繁荣','守护森林','城内不得燃火','城民不得说谎','所有债务必须偿还']) {
  scenario(text,[{kind:'oath',text},...play('observe')]);
}
scenario('debt-six-turn-route',[{kind:'oath',text:'所有债务必须偿还'},...['forge','forest','farm','investigate','forge','investigate'].map(action=>({kind:'action',action}))]);
scenario('debt-ai-review',[{kind:'oath',text:'所有债务必须偿还'},...['forge','forest','farm','investigate','forge','investigate'].map(action=>({kind:'action',action})),{kind:'ai',data:{summary:'任期资源复核',effects:[{cityId:'ember',delta:{peace:-3},reason:'模拟摩擦'}]}}]);
scenario('fire-actions',[{kind:'oath',text:'城内不得燃火'},...['forest','forge','forge','forest','reveal'].map(action=>({kind:'action',action}))]);
scenario('silence-actions',[{kind:'oath',text:'城民不得说谎'},...['investigate','reveal','reveal'].map(action=>({kind:'action',action}))]);
for(const text of ['永不缺粮','永远和平','守护贸易繁荣','守护森林']) scenario('paid-'+text,[{kind:'oath',text},{kind:'action',action:'forge'},{kind:'ai',data:{summary:'支付后守护边界',effects:[{cityId:'ember',delta:{food:-3,peace:-3,trade:-3,ecology:-3},reason:'模拟影响'}]}}]);
scenario('anchor-sleep-resume',[{kind:'oath',text:'城市位置不变'},{kind:'patch',city:'ember',values:{peace:0}},{kind:'action',action:'observe'},{kind:'patch',city:'ember',values:{peace:60}},{kind:'action',action:'observe'}]);
scenario('mixed-and-replacement',Array.from({length:60},(_,i)=>[...(i%5===0?[{kind:'oath',text:['守护森林','永不缺粮','所有债务必须偿还'][i%3]}]:[]),{kind:'action',action:['farm','investigate','build','restore','forest','forge','observe'][i%7]}]).flat());
for(let seed=0;seed<8;seed++) scenario('random-'+seed,play('observe'),seed);
for(const seed of [2147483648,4294967295]) scenario('uint32-'+seed,play('observe'),seed);
function pairFixture(extra={}) {
  const s=initial(123);s.cities=s.cities.slice(0,2);
  for(const c of s.cities) Object.assign(c,{x:400,y:300,ecology:50,territory:{shape:'O',angle:0,spin:0},eventSeen:['hunger','unrest','seed','market','refugees','feast','craft','isolation','torch'],vx:-Math.sin(.2+c.origin.x)*1.1,vy:-Math.cos(1/6+c.origin.y)*1.1});
  Object.assign(s.cities[0],extra);
  return {kind:'worldPatch',values:{cities:s.cities}};
}
scenario('full-overlap',[pairFixture(),...play('observe')]);
scenario('exact-contact',[pairFixture(),{kind:'patch',city:'grove',values:{x:528}},...play('observe')]);
scenario('boundary-one-cell',[pairFixture(),{kind:'patch',city:'grove',values:{x:592}},{kind:'action',action:'observe'}]);
scenario('boundary-outside',[pairFixture(),{kind:'patch',city:'grove',values:{x:592.01}},{kind:'action',action:'observe'}]);
scenario('diplomacy-three-rounds',[pairFixture(),{kind:'oath',text:'守护贸易繁荣'},{kind:'action',action:'mediate',targetId:'grove'},{kind:'action',action:'mediate',targetId:'grove'},...play('observe')]);
scenario('diplomacy-refusals',[pairFixture({trade:7}),{kind:'action',action:'mediate',targetId:'grove'},{kind:'action',action:'mediate',targetId:'ember'},{kind:'action',action:'mediate',targetId:'bad'}]);
scenario('diplomacy-third-city',[pairFixture(),{kind:'worldPatch',values:{cities:[...pairFixture().values.cities,{...structuredClone(pairFixture().values.cities[1]),id:'third',name:'第三城'}]}},{kind:'action',action:'mediate',targetId:'grove'},...play('observe')]);
const economic=[pairFixture({ecology:70}),{kind:'patch',city:'grove',values:{x:560}}];
scenario('economic-debt-route',[...economic,{kind:'oath',text:'所有债务必须偿还'},...['forge','forest','farm','investigate','forge','investigate'].map(action=>({kind:'action',action})),{kind:'ai',data:{summary:'任期资源复核',effects:[{cityId:'ember',delta:{peace:-3},reason:'模拟摩擦'}]}}]);
const capCities=initial(123).cities;
capCities.forEach((c,i)=>{Object.assign(c,{x:[400,528,272,400,400,528][i],y:[300,300,300,428,172,428][i],ecology:50,eventSeen:['hunger','unrest','seed','market','refugees','feast','craft','isolation','torch'],territory:{shape:'O',angle:0,spin:0},vx:-Math.sin(.2+c.origin.x)*1.1,vy:-Math.cos(1/6+c.origin.y)*1.1});});
scenario('trade-income-cap',[{kind:'worldPatch',values:{cities:capCities}},{kind:'action',action:'observe'}]);
// Keep the large single-line fixture outside res:// so the editor cannot
// accidentally reopen/highlight it while restoring its previous session.
await mkdir(new URL('../godot-test-data/',import.meta.url),{recursive:true});
await writeFile(new URL('../godot-test-data/reference.json',import.meta.url),JSON.stringify(scenarios));
console.log(`Generated ${scenarios.length} scenarios, ${scenarios.reduce((n,s)=>n+s.ops.length,0)} operations (including rejected actions).`);
