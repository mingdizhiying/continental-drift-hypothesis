// 每城独立的旧城叙事状态；由世界引擎统一推进时间。
export const legacyLaws = {
 fire:{name:'城内不得燃火',text:'城内不得燃火',detail:'安定≥35；采集+3物资且不减信任，修复消耗2物资但仅+1屏障。'},
 silence:{name:'城民不得说谎',text:'城民不得说谎',detail:'安定≥35；调查+2信任，公开秘密+2屏障但−2信任。'},
 memory:{name:'所有债务必须偿还',text:'所有债务必须偿还',detail:'安定≥35；修复消耗3物资，获得+3屏障。'}
};
export const barrierActions = {
 forge:{name:'修复圣光屏障',place:'余烬工坊 · 铁匠烬',hint:'物资−2，屏障+2；法则改变效率'},
 forest:{name:'采集灵木',place:'无声林地 · 树灵苔',hint:'物资+2，信任−1；禁火时+3且不减信任'},
 investigate:{name:'倾听与调查',place:'旧誓广场 · 守屏人祈',hint:'信任+1；禁谎时+2'},
 reveal:{name:'公开秘密，取回光核',place:'旧誓广场 · 守屏人祈',hint:'每城一次：屏障+2，信任−1；禁谎时−2'}
};
export function barrierOutcome(c){return c.barrier<6?{title:'长夜',text:'圣光屏障未能成形，居民退往林地，在混沌中等待下一任使者。'}:c.trust>=5?{title:'共誓',text:'圣光屏障展开，城民与树灵共同承担守护的代价。'}:{title:'孤光',text:'圣光屏障已经展开，但居民不再信任彼此。你守住了城市，却失去了它的声音。'};}
export function applyBarrierAction(c,action,law){
 const before={supply:c.supply,trust:c.trust,barrier:c.barrier};let story;
 if(action==='forge'){
  if(c.barrier>=6)throw new Error('圣光屏障已完成，无须重复修复。');
  const cost=law==='memory'?3:2;if(c.supply<cost)throw new Error(`物资不足：本次修复需要${cost}份物资。`);
  c.supply-=cost;c.barrier+=law==='fire'?1:law==='memory'?3:2;
  story=law==='fire'?'炉火无法点燃，铁匠以冷锻艰难修复光核。':law==='memory'?'铁匠偿还庇护之恩，投入珍藏材料修复光核。':'铁匠锻出光核，修复城市上空的圣光屏障。';
 }else if(action==='forest'){c.supply+=law==='fire'?3:2;c.trust-=law==='fire'?0:1;story=law==='fire'?'树灵不再惧怕火焰，主动赠予三份灵木。':'你带走两份灵木，树灵对城民的信任降低。';}
 else if(action==='investigate'){c.trust+=law==='silence'?2:1;story=law==='silence'?'谎言无法出口，守屏人承认藏起光核，居民开始相信调查。':'你耐心听取城民的证词，逐渐获得他们的信任。';}
 else if(action==='reveal'){if(c.revealed)throw new Error('本城秘密已经公开，光核已经取回。');c.revealed=true;c.barrier+=2;c.trust-=law==='silence'?2:1;story='你公开守屏人的秘密，取回两枚光核；居民争论谁该承担责任。';}
 else throw new Error('未知屏障行动');
 c.trust=Math.max(0,Math.min(10,c.trust));c.barrier=Math.min(6,c.barrier);
 const labels={supply:'物资',trust:'信任',barrier:'屏障'};
 return `${story}（${Object.keys(before).map(k=>`${labels[k]} ${c[k]-before[k]>=0?'+':''}${c[k]-before[k]}`).join('，')}）`;
}
