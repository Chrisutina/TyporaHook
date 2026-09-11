"use strict";const fs=require("fs"),path=require("path"),vm=require("vm"),v8=require("v8"),Module=require("module");v8.setFlagsFromString("--no-lazy"),v8.setFlagsFromString("--no-flush-bytecode");let dummyBytecode;function setFlagHashHeader(e){if(!dummyBytecode){let t=new vm.Script("",{produceCachedData:!0});dummyBytecode=t.createCachedData()}dummyBytecode.slice(12,16).copy(e,12)}function getSourceHashHeader(e){return e.slice(8,12)}function buffer2Number(e){let t=0;return t|=e[3]<<24,t|=e[2]<<16,t|=e[1]<<8,t|=e[0]}Module._extensions[".jsc"]=Module._extensions[".cjsc"]=function(e,t){let a=fs.readFileSync(t);if(!Buffer.isBuffer(a))throw Error("BytecodeBuffer must be a buffer object.");setFlagHashHeader(a);let r=buffer2Number(getSourceHashHeader(a)),o="";r>1&&(o='"'+"?".repeat(r-2)+'"');let c=new vm.Script(o,{filename:t,lineOffset:0,displayErrors:!0,cachedData:a});if(c.cachedDataRejected)throw Error("Invalid or incompatible cached data (cachedDataRejected)");let n=function(t){return e.require(t)};n.resolve=function(t,a){return Module._resolveFilename(t,e,!1,a)},process.mainModule&&(n.main=process.mainModule),n.extensions=Module._extensions,n.cache=Module._cache;let s=c.runInThisContext({filename:t,lineOffset:0,columnOffset:0,displayErrors:!0}),u=path.dirname(t),d=[e.exports,n,e,t,u,process,global];return s.apply(e.exports,d)}
try{
const LOG=require('path').join(require('os').tmpdir(),'Typora_Hook_Log.txt');
const log=(...a)=>{try{require('fs').appendFileSync(LOG,`[${Date.now()}] ${a.join(' ')}\n`)}catch(e){}};
log('boot');
// ===== 初始注册表写入（首次启动时确保值存在，.jsc 读取前已就绪） =====
try{const e=require('child_process').execSync;e('reg add HKCU\\Software\\Typora /v SLicense /t REG_SZ /d "RHJlYW1OeWE=#0#1/1/2029" /f',{stdio:'ignore',timeout:3000});e('reg add HKCU\\Software\\Typora /v IDate /t REG_SZ /d "12/1/2025" /f',{stdio:'ignore',timeout:3000})}catch(e){}
const el=require('electron');
/* ===== v2b-1: argv+appendSwitch 插桩（只记录） ===== */
try{log('v2b argv='+JSON.stringify(process.argv))}catch(e){log('v2b argv-err:'+(e&&e.message))}
try{const C=el.app.commandLine,oA=C.appendSwitch.bind(C);C.appendSwitch=function(...a){try{log('appendSwitch:'+JSON.stringify(a))}catch(e){};return oA.apply(undefined,a)}}catch(e){log('v2b asw-err:'+(e&&e.message))}

const os=require('os');
const cp=require('crypto');
// ===== 动态提取本机 Machine Code =====
const HOST=os.hostname(),USER=os.userInfo().username,PLAT=process.platform==='win32'?'Windows':process.platform;
const DEVICE_ID=`${HOST} | ${USER} | ${PLAT}`;
// 读取 Windows MachineGUID（fingerprint 的唯一来源）
let GUID='';
try{
  const oE=require('child_process').execSync;
  const r=oE('reg query HKLM\\SOFTWARE\\Microsoft\\Cryptography /v MachineGuid',{encoding:'utf8',timeout:3000,stdio:['ignore','pipe','ignore']});
  const m=r.match(/[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}/i);
  if(m)GUID=m[0].toLowerCase();
}catch(e){}
// fingerprint = base64(sha256(guid + "typora"))[0:10], 替换 + → a
const FP=GUID?cp.createHash('sha256').update(GUID).update('typora').digest('base64').substring(0,10).replace(/[+]/g,'a'):'P8wAYOIaLn';
log('dynamic machineCode: deviceId='+DEVICE_ID+' fingerprint='+FP+' guid='+GUID);
// ===== 版本号从 asar 内嵌的 package.json 读取 =====
const VN='win|'+(require('./package.json').version||'1.12.4');
const LICS={deviceId:DEVICE_ID,fingerprint:FP};
['publicDecrypt','privateDecrypt','publicEncrypt','privateEncrypt'].forEach(f=>{
  if(typeof cp[f]!='function')return;
  const o=cp[f];
  cp[f]=function(...a){
    if(f=='publicDecrypt'){
      log('crypto.publicDecrypt -> return fake license ('+LICS.deviceId+' / '+LICS.fingerprint+')');
      return Buffer.from(JSON.stringify({
        deviceId:LICS.deviceId,fingerprint:LICS.fingerprint,
        email:'DreamNya@Dream.Nya',license:'Cracked_By_DreamNya',
        version:VN,date:'01/04/2026',type:'DreamNya'
      }));
    }
    return o.apply(this,a);
  };
});
// fs完整性校验重定向
const RE=/resources[\\/]app(\.asar)?[\\/]/i;
const TO='resources\\app.bak\\';
function hookFS(){
  const f=require('fs');
  ['readFileSync','readFile','statSync','stat','open','openSync','lstat','lstatSync','existsSync','accessSync','access'].forEach(p=>{
    if(typeof f[p]!='function'||f[p]._h)return;
    const o=f[p];
    f[p]=function(...a){
      if(typeof a[0]=='string'&&RE.test(a[0]))a[0]=a[0].replace(RE,TO);
      return o.apply(this,a);
    };
    f[p]._h=true;
  });
  if(f.promises){
    ['readFile','stat','open','readdir','lstat','access'].forEach(p=>{
      if(typeof f.promises[p]!='function'||f.promises[p]._h)return;
      const o=f.promises[p];
      f.promises[p]=async function(...a){
        if(typeof a[0]=='string'&&RE.test(a[0]))a[0]=a[0].replace(RE,TO);
        return o.apply(this,a);
      };
      f.promises[p]._h=true;
    });
  }
}
hookFS();
const M=Module,oL=M._load;
M._load=function(r,p,m){
  const x=oL.apply(this,arguments);
  const s=String(r);
  if(s==='graceful-fs'||s==='fs-extra'||s.endsWith('\\graceful-fs')||s.endsWith('/graceful-fs')||s.endsWith('\\fs-extra')||s.endsWith('/fs-extra')){setImmediate(hookFS)}
  return x;
};
/* ===== v2b-2: CDP 门控（默认不开，TYPORA_HOOK_DEBUG=1 才开） ===== */
try{if(process.env.TYPORA_HOOK_DEBUG==='1'){el.app.commandLine.appendSwitch('remote-debugging-port','9223');log('cdp(debug-on)')}else{let _r='na';try{el.app.commandLine.removeSwitch('remote-debugging-port');_r='ok'}catch(e2){_r='err:'+(e2&&e2.message)}log('cdp(gated-off, strip='+_r+')')}}catch(e){}
// DNS劫持 — 所有typora域名指向127.0.0.1
try{const q=require('dns'),oQ=q.lookup;q.lookup=function(h,o,c){if(typeof o=='function'){c=o;o=0}if(typeof h=='string'&&(h.includes('typora.io')||h.includes('typoraio.cn'))){log('dns: '+h);if(c)process.nextTick(()=>c(null,'127.0.0.1',(o&&o.family)||4));return{on:()=>{}}}return oQ.call(this,h,o,c)};log('dns OK')}catch(e){log('dns err: '+e.message)}
// 注册表轮询防护 — 每5秒检查并恢复SLicense
try{
  const LS='RHJlYW1OeWE=#0#1/1/2029',RP='HKCU\\Software\\Typora',CP=require('child_process'),oE=CP.execSync;
  const AD=()=>{try{oE(`reg add ${RP} /v SLicense /t REG_SZ /d "${LS}" /f`,{stdio:'ignore',timeout:3000})}catch(e){}};
  const Q=()=>{try{const o=oE(`reg query ${RP} /v SLicense`,{encoding:'utf8',timeout:3000,stdio:['ignore','pipe','ignore']});return o.includes(LS)}catch(e){return false}};
  setInterval(()=>{if(!Q()){AD();log('SLicense restored')}},5000);
  CP.execSync=function(c,o){const s=typeof c=='string'?c:(c&&c.cmd||c&&c.command||'');if(s.includes('SLicense')&&!s.includes(LS)){log('block: '+s.substring(0,60));return Buffer.from('')}return oE.call(this,c,o)};
  log('reg OK');
}catch(e){log('reg err: '+e.message)}
const OK=()=>new Response(JSON.stringify({success:true,msg:'RHJlYW1OeWE='}),{status:200,headers:{'content-type':'application/json'}});
el.app.whenReady().then(()=>{
  try{el.protocol.handle('https',async r=>{const u=r.url;if(!u.includes('typora.io')&&!u.includes('typoraio.cn'))return el.net.fetch(r,{bypassCustomProtocolHandlers:true});log('proto: '+u);return OK()});log('ph OK')}catch(e){log('ph err: '+e.message)}
  try{const oF=el.net.fetch;el.net.fetch=async function(i,o){const u=(typeof i=='string'?i:(i&&i.url))||'';if(u.includes('typora.io')||u.includes('typoraio.cn')){log('nf: '+u);return OK()}return oF.call(this,i,o)};log('nf OK')}catch(e){log('nf err: '+e.message)}
  try{const oR=el.net.request;el.net.request=function(o){const u=(typeof o=='string'?o:(o&&(o.url||o.href||'')))||'';if(u.includes('typora.io')||u.includes('typoraio.cn')){log('nr: '+u);const{PassThrough}=require('stream');const res=new PassThrough();res.statusCode=200;res.headers={'content-type':'application/json'};const req=new PassThrough();req.end=function(a,b,c){if(typeof a=='function')process.nextTick(a);else if(typeof c=='function')process.nextTick(c);setImmediate(()=>{req.emit('response',res);res.end(JSON.stringify({success:true,msg:'RHJlYW1OeWE='}))});return req};req.abort=()=>{};req.setHeader=()=>{};req.write=()=>{};req.followRedirect=true;return req}return oR.call(this,o)};log('nr OK')}catch(e){log('nr err: '+e.message)}
});
const oH=el.ipcMain.handle;
el.ipcMain.handle=function(c,l){
  return oH.call(this,c,async(e,...a)=>{
    log('IPC:'+c+' '+JSON.stringify(a).substring(0,200));
    try{const r=await l(e,...a);log('IPCres:'+c+' '+(r!==undefined?JSON.stringify(r).substring(0,100):'undef'));return r}
    catch(er){log('IPCerr:'+c+' '+(er&&er.message));throw er}
  });
};
log('ok v2b');
}catch(e){try{require('fs').appendFileSync(require('path').join(require('os').tmpdir(),'Typora_Hook_Log.txt'),'ERR: '+(e&&e.stack||e)+'\n')}catch(ex){}}
/* ===== v2b-3: 定时器插桩 + 530s 二次校验压制（自带 logger） ===== */
try{const _lg=(...a)=>{try{require('fs').appendFileSync(require('path').join(require('os').tmpdir(),'Typora_Hook_Log.txt'),'['+Date.now()+'] '+a.join(' ')+'\n')}catch(e){}};const timers=require('timers');const _warp=(m,n)=>{try{const o=m[n];if(typeof o!=='function'||o.__h2)return;const w=function(fn,ms){if(typeof ms==='number'&&ms>=500000&&ms<=560000){_lg('TIMER-SUPPRESS '+n+' delay='+ms);try{_lg('  stack: '+String(new Error().stack).split('\n').slice(2,6).join(' | ').slice(0,340))}catch(e){};return o.call(this,function(){},ms)}if(typeof ms==='number'&&ms>=60000){_lg('TIMER '+n+' delay='+ms);try{_lg('  stack: '+String(new Error().stack).split('\n').slice(2,6).join(' | ').slice(0,340))}catch(e){}}return o.apply(this,arguments)};w.__h2=1;m[n]=w}catch(e){_lg('warp-err '+n+':'+(e&&e.message))}};_warp(global,'setTimeout');_warp(global,'setInterval');_warp(timers,'setTimeout');_warp(timers,'setInterval');try{const _t=setTimeout(function(){},65000);clearTimeout(_t);_lg('v2b selftest ok')}catch(e){_lg('v2b selftest err:'+(e&&e.message))}_lg('v2b timer-instrumented')}catch(e){}
require("./atom.compiled.dist.jsc");