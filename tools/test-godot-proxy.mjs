// Exercises the real local proxy with a fake provider; never loads .env or real keys.
import assert from 'node:assert/strict';
import http from 'node:http';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {fileURLToPath} from 'node:url';
import {initial,advance,parseOath} from './web-baseline/world.js';

let responseData={};let providerRequests=0;
const provider=http.createServer(async(req,res)=>{
  let body='';for await(const part of req)body+=part;
  const input=JSON.parse(body);
  assert.equal(req.headers.authorization,'Bearer fake-local-test-key');
  assert.equal(input.model,'fake-local-test-model');
  assert.ok(input.messages[0].content.includes('主动支付'));
  providerRequests++;
  res.setHeader('Content-Type','application/json');
  res.end(JSON.stringify({choices:[{message:{content:JSON.stringify(responseData)}}]}));
});
await new Promise(resolve=>provider.listen(0,'127.0.0.1',resolve));
const proxy=spawn(process.execPath,['tools/godot-proxy.mjs'],{
  cwd:fileURLToPath(new URL('../',import.meta.url)),windowsHide:true,
  env:{...process.env,PORT:'0',LLM_ENDPOINT:`http://127.0.0.1:${provider.address().port}/model`,LLM_MODEL:'fake-local-test-model',LLM_API_KEY:'fake-local-test-key'},
});
let errors='';proxy.stderr.on('data',d=>errors+=d);
try{
  const address=await new Promise((resolve,reject)=>{
    let output='';const timer=setTimeout(()=>reject(Error('Proxy startup timed out: '+errors)),5000);
    proxy.on('error',reject);
    proxy.stdout.on('data',d=>{output+=d;const match=output.match(/http:\/\/127\.0\.0\.1:\d+/);if(match){clearTimeout(timer);resolve(match[0]);}});
  });
  async function request(task,input,status=200){
    const result=await fetch(address+'/api/world',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({task,...input}),signal:AbortSignal.timeout(5000)});
    assert.equal(result.status,status);return result.json();
  }
  const state=initial(123);
  for(const text of ['固定位置','永不缺粮','永远和平','守护繁荣','守护森林','城内不得燃火','城民不得说谎','所有债务必须偿还']){
    const oath=parseOath(text);responseData={accepted:true,oath:{type:oath.type,condition:oath.condition,explanation:oath.explanation}};
    const result=await request('oath',{state,text});assert.equal(result.oath.type,oath.type);
  }
  responseData={accepted:false,reason:'模拟拒绝'};
  assert.equal((await request('oath',{state,text:'守护森林'})).accepted,false);
  responseData={accepted:true,oath:{type:'code',condition:{metric:'trade',min:0},explanation:'不可执行'}};
  await request('oath',{state,text:'守护森林'},502);
  const next=advance(state,'observe');
  responseData={summary:'模拟影响',effects:[{cityId:'ember',delta:{peace:-3},reason:'模拟摩擦'}]};
  await request('turn',{state:next,before:state,action:'observe'});
  responseData.effects[0].delta.peace=4;
  await request('turn',{state:next,before:state,action:'observe'},502);
  responseData.effects[0].delta.peace=1;
  responseData.effects.push(structuredClone(responseData.effects[0]));
  await request('turn',{state:next,before:state,action:'observe'},502);
  let endingState=state;for(let i=0;i<60;i++)endingState=advance(endingState,'observe');
  responseData={title:'模拟结局',text:'仅验证本地协议',evidence:['第60轮完成结算']};
  assert.equal((await request('ending',{state:endingState})).title,'模拟结局');
  const countBefore=providerRequests;
  await request('ending',{state:next},400);
  assert.equal(providerRequests,countBefore,'Invalid early ending reached provider');
  assert.equal((await fetch(address+'/')).status,404);
  assert.equal(errors,'');
  console.log(`PASS: actual Godot proxy with FAKE provider (${providerRequests} requests), eight oath types, rejection, validation, bounded effects, duplicates and final-only ending. No live model tested.`);
}finally{
  if(proxy.exitCode===null){proxy.kill();await once(proxy,'exit');}
  await new Promise(resolve=>provider.close(resolve));
}
