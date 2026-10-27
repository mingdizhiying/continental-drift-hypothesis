export const resourceNames={food:'粮食',peace:'安定',trade:'繁荣',ecology:'生态'};
export const legacyLaws={
 fire:{name:'城内不得燃火',text:'城内不得燃火',detail:'安定≥35；采集改为繁荣+9、生态−4；修复不耗生态，但仅+1屏障。'},
 silence:{name:'城民不得说谎',text:'城民不得说谎',detail:'安定≥35；调查安定+11；公开秘密的安定代价升至24。'},
 memory:{name:'所有债务必须偿还',text:'所有债务必须偿还',detail:'安定≥35；修复消耗24繁荣、9粮食、4生态、5安定，屏障+3。'}
};
// 同一声明同时驱动按钮、支付校验、执行和历史，避免显示与实际消耗分离。
export const cityActions={
 farm:{name:'组织耕种',place:'农田',cost:{trade:2,ecology:3},gain:{food:10}},
 build:{name:'建设集市',place:'集市',cost:{food:4,ecology:4},gain:{trade:9}},
 restore:{name:'修复林地',place:'林地',cost:{food:3,trade:5},gain:{ecology:10}},
 investigate:{name:'倾听与调解',place:'旧誓广场 · 守屏人祈',cost:{food:3,trade:2},gain:{peace:7}},
 forest:{name:'采集灵木',place:'无声林地 · 树灵苔',cost:{ecology:10,peace:4},gain:{trade:12}},
 forge:{name:'修复圣光屏障',place:'余烬工坊 · 铁匠烬',cost:{trade:18,food:7,ecology:4,peace:3},gain:{barrier:2}},
 reveal:{name:'公开秘密，取回光核',place:'旧誓广场 · 守屏人祈',cost:{peace:16,trade:4},gain:{barrier:2}},
 observe:{name:'观察世界',place:'瞭望台',cost:{},gain:{}}
};
export function actionSpec(action,law){
 const source=cityActions[action];if(!source)throw new Error('未知行动');const spec=structuredClone(source);
 if(action==='forge'&&law==='memory'){spec.cost={trade:24,food:9,ecology:4,peace:5};spec.gain.barrier=3;}
 if(action==='forge'&&law==='fire'){delete spec.cost.ecology;spec.gain.barrier=1;}
 if(action==='forest'&&law==='fire'){spec.cost={ecology:4};spec.gain={trade:9};}
 if(action==='investigate'&&law==='silence')spec.gain.peace=11;
 if(action==='reveal'&&law==='silence')spec.cost.peace=24;
 return spec;
}
export function actionBlock(c,action,law){
 const spec=actionSpec(action,law);
 if((action==='forge'||action==='reveal')&&c.barrier>=6)return '圣光屏障已完成';
 if(action==='reveal'&&c.revealed)return '本城秘密已经公开';
 const missing=Object.entries(spec.cost).filter(([k,v])=>c[k]<v).map(([k,v])=>`${resourceNames[k]}需${v}（现有${c[k]}）`);
 return missing.length?'资源不足：'+missing.join('，'):'';
}
export function applyCityAction(c,action,law){
 const spec=actionSpec(action,law),blocked=actionBlock(c,action,law);if(blocked)throw new Error(blocked);
 const before=structuredClone(c);
 for(const [k,v]of Object.entries(spec.cost))c[k]-=v;
 for(const [k,v]of Object.entries(spec.gain))c[k]=Math.min(k==='barrier'?6:100,c[k]+v);
 if(action==='reveal')c.revealed=true;
 const labels={...resourceNames,barrier:'屏障'};
 const changes=Object.keys(labels).filter(k=>c[k]!==before[k]).map(k=>`${labels[k]} ${c[k]>before[k]?'+':''}${c[k]-before[k]}`);
 return {cost:spec.cost,text:`${spec.name}（${changes.join('，')||'无直接收益，仍承担世界消耗'}）`};
}
export function barrierOutcome(c){return c.barrier<6?{title:'长夜',text:'圣光屏障未能成形，居民退往林地，等待下一任使者。'}:c.peace>=60&&c.food>=20?{title:'共誓',text:'圣光屏障展开，安定与粮食支撑城民共同承担守护的代价。'}:{title:'孤光',text:'圣光屏障已展开，但安定或口粮不足，庇护之下仍有人承受代价。'};}
