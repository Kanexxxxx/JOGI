"use strict";
const fs = require('node:fs');
const crypto = require('node:crypto');
function alive(pid) { if(!Number.isInteger(pid)||pid<=0)return false;try{process.kill(pid,0);return true;}catch(e){return e.code==='EPERM';} }
function read(file) {try{return JSON.parse(fs.readFileSync(file,'utf8'));}catch{return null;}}
function same(a,b) {return Boolean(a&&b&&a.pid===b.pid&&a.nonce===b.nonce);}
function claim(file) {
 const current=read(file);
 if(current&&alive(current.pid))throw new Error('Outro login Kwai jÃ¡ controla a solicitaÃ§Ã£o. Nenhum processo encerrado.');
 if(fs.existsSync(file)) {if(!current)throw new Error('SolicitaÃ§Ã£o Kwai invÃ¡lida: requer revisÃ£o manual.');fs.unlinkSync(file);}
 const owner={pid:process.pid,nonce:crypto.randomUUID(),started_at:Date.now()};
 fs.writeFileSync(file,JSON.stringify(owner),{flag:'wx'});return owner;
}
function release(file,owner) {if(same(read(file),owner))fs.unlinkSync(file);}
function acknowledge(file,request) {
 if(!same(read(file),request))return false;
 const temp=file+'.released.'+process.pid+'.tmp';
 fs.writeFileSync(temp,JSON.stringify({...request,released_by:process.pid,released_at:Date.now()}));
 fs.renameSync(temp,file+'.released');return true;
}
async function waitForRelease(file,request,{timeoutMs=30000,pollMs=200,ownerFile=file+'.owner',sleep=ms=>new Promise(r=>setTimeout(r,ms))}={}) {
 const deadline=Date.now()+timeoutMs;
 while(Date.now()<deadline) {
  if(!same(read(file),request))throw new Error('SolicitaÃ§Ã£o de login alterada. Nenhum perfil serÃ¡ aberto.');
  if(same(read(file+'.released'),request))return;
  const collector=read(ownerFile);
  if(!collector||!alive(collector.pid))throw new Error('Coletor atualizado não confirmou propriedade/liberação do perfil. Não force o login; solicite atualização autorizada do coletor.');
  await sleep(pollMs);
 }
 throw new Error('Coletor nÃ£o confirmou a liberaÃ§Ã£o do perfil em 30s. Nenhum processo foi encerrado; solicite atualizaÃ§Ã£o segura do coletor.');
}
module.exports={read,claim,release,acknowledge,waitForRelease,same,alive};
