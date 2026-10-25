'use strict';
// Local operator-only Chromium profile. No token in a URL, page text, logs or Git.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
function playwright(){for(const location of ['playwright',path.join(os.homedir(),'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright')]){try{return require(location);}catch(_){}}throw new Error('Playwright local indisponível.');}
(async()=>{
 const {chromium}=playwright();
 const base=path.join(process.env.LOCALAPPDATA,'JOGI');
 const candidates=[path.join(process.env.ProgramFiles||'C:/Program Files','Google/Chrome/Application/chrome.exe')];
 const installed=path.join(process.env.LOCALAPPDATA,'ms-playwright');
 if(fs.existsSync(installed))for(const folder of fs.readdirSync(installed).sort().reverse())if(folder.startsWith('chromium-'))candidates.push(path.join(installed,folder,'chrome-win64/chrome.exe'));
 const executablePath=candidates.find(file=>fs.existsSync(file));
 const context=await chromium.launchPersistentContext(path.join(base,'operator-browser'),{headless:false,executablePath,viewport:{width:1380,height:940}});
 let ready=0;
 for(const [platform,port] of [['tiktok',8765],['kwai',8766]]){
  try {
   const origin=`http://127.0.0.1:${port}`;
   const health=await context.request.get(origin+'/health');
   if(!health.ok())throw new Error('backend indisponível');
   const info=await health.json();
   if(info.platform!==platform || typeof info.account!=='string')throw new Error('instância divergente');
   const key=crypto.createHash('sha256').update(info.account).digest('hex').slice(0,16);
   const file=path.join(base,'live_bridge',platform,'production/accounts',key,'operator-token.key');
   const token=fs.readFileSync(file,'utf8').trim();
   const auth=await context.request.get(origin+'/api/admin/session',{headers:{'X-JOGI-Token':token}});
   if(!auth.ok())throw new Error('autenticação recusada');
   const page=await context.newPage();await page.goto(origin+'/admin',{waitUntil:'domcontentloaded'});
   await page.locator('#auth-unlock-section').waitFor({state:'hidden',timeout:12000});
   console.log(`${platform}: painel autenticado para @${info.account}.`);ready++;
  } catch(error){console.error(`${platform}: ${error.code==='ENOENT'?'chave local ainda não disponível; abra o launcher primeiro':error.message}`);}
 }
 if(!ready){await context.close();process.exitCode=1;return;}
 for(const page of context.pages()){if(page.url()==='about:blank')await page.close();}
 console.log('Somente painéis locais. Nenhuma transmissão iniciada. Feche o navegador para encerrar este atalho.');
 await new Promise(resolve=>context.once('close',resolve));
})().catch(()=>{console.error('Não foi possível abrir os painéis. Se este navegador dedicado já estiver aberto, utilize suas abas existentes.');process.exitCode=1;});
