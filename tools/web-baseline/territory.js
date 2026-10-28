// Geometry is shared by simulation and SVG: four rotated squares, not bounding circles.
export const CELL=64, EPS=1e-7;
export const shapes={I:[[0,0],[1,0],[2,0],[3,0]],O:[[0,0],[1,0],[0,1],[1,1]],T:[[0,0],[1,0],[2,0],[1,1]],S:[[1,0],[2,0],[0,1],[1,1]],Z:[[0,0],[1,0],[1,1],[2,1]],J:[[0,0],[0,1],[1,1],[2,1]],L:[[2,0],[0,1],[1,1],[2,1]]};
export function randomSource(seed){let n=seed>>>0;return()=>{n+=0x6D2B79F5;let t=n;t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);return((t^t>>>14)>>>0)/4294967296;};}
export function createTerritory(rng){return {shape:Object.keys(shapes)[Math.floor(rng()*7)],angle:rng()*360,spin:(1.5+rng()*2.5)*(rng()<.5?-1:1)};}
export function territoryPolygons(c){
 const t=c.territory,blocks=shapes[t.shape],cx=blocks.reduce((v,b)=>v+b[0]+.5,0)/4,cy=blocks.reduce((v,b)=>v+b[1]+.5,0)/4;
 const a=t.angle*Math.PI/180,cos=Math.cos(a),sin=Math.sin(a);
 return blocks.map(([x,y])=>[[x,y],[x+1,y],[x+1,y+1],[x,y+1]].map(([u,v])=>{u=(u-cx)*CELL;v=(v-cy)*CELL;return{x:c.x+u*cos-v*sin,y:c.y+u*sin+v*cos};}));
}
const cross=(a,b,p)=>(b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x);
export function intersection(subject,clip){
 let out=subject;
 for(let i=0;i<clip.length;i++){
  const a=clip[i],b=clip[(i+1)%clip.length],input=out;out=[];
  for(let j=0;j<input.length;j++){
   const p=input[j],q=input[(j+1)%input.length],cp=cross(a,b,p),cq=cross(a,b,q),ip=cp>=-EPS,iq=cq>=-EPS;
   if(ip)out.push(p);
   if(ip!==iq){const t=cp/(cp-cq);out.push({x:p.x+(q.x-p.x)*t,y:p.y+(q.y-p.y)*t});}
  }
 }
 return out;
}
const area=p=>Math.abs(p.reduce((s,a,i)=>{const b=p[(i+1)%p.length];return s+a.x*b.y-a.y*b.x;},0))/2;
function pointSegment(p,a,b){const dx=b.x-a.x,dy=b.y-a.y,t=Math.max(0,Math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/(dx*dx+dy*dy)));return Math.hypot(p.x-a.x-t*dx,p.y-a.y-t*dy);}
export function territoryRelation(a,b){
 const ap=territoryPolygons(a),bp=territoryPolygons(b),overlaps=[];let overlapArea=0,gap=Infinity;
 for(const p of ap)for(const q of bp){const clip=intersection(p,q),size=area(clip);if(size>EPS){overlaps.push(clip);overlapArea+=size;}
  for(let i=0;i<4;i++)for(let j=0;j<4;j++)gap=Math.min(gap,pointSegment(p[i],q[j],q[(j+1)%4]),pointSegment(q[j],p[i],p[(i+1)%4]));
 }
 if(overlapArea>EPS)gap=0;
 return {gap,overlapArea,overlapRatio:overlapArea/(4*CELL*CELL),overlaps,type:overlapArea>EPS?'冲突':gap<=CELL+EPS?'贸易':'隔绝'};
}
export function territoryRadius(c){return Math.max(...territoryPolygons({...c,x:0,y:0}).flat().map(p=>Math.hypot(p.x,p.y)));}
