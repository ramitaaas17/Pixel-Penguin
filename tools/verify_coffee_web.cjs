const {chromium} = require('../.tools/web-test/node_modules/playwright');
const fs = require('fs');
(async () => {
  fs.mkdirSync('docs/minigames', {recursive:true});
  const browser = await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--enable-unsafe-swiftshader']});
  try {
    const page = await browser.newPage({viewport:{width:960,height:600}});
    const errors=[];
    page.on('pageerror', e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error'){errors.push(m.text());console.error(m.text());}});
    await page.addInitScript(() => {
      window.__coffeeAudio = [];
      const original = AudioNode.prototype.connect;
      AudioNode.prototype.connect = function(target, ...args) {
        const result = original.call(this, target, ...args);
        if(target === this.context.destination) {
          const analyser = this.context.createAnalyser();
          analyser.fftSize = 1024;
          original.call(this, analyser);
          window.__coffeeAudio.push(analyser);
        }
        return result;
      };
    });
    await page.goto(process.env.COFFEE_TEST_BASE_URL || 'http://localhost:3000/');
    await page.waitForFunction(()=>!document.getElementById('status'),null,{timeout:60000});
    await page.waitForTimeout(1000);
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    await page.mouse.click(192,367);
    await page.waitForTimeout(6500);
    await page.keyboard.press('e');
    await page.waitForTimeout(500);
    const intro=await page.screenshot({path:'docs/minigames/web-intro.png'});
    const pixel=await page.evaluate(async b64=>{
      const data=Uint8Array.from(atob(b64),c=>c.charCodeAt(0));
      const img=await createImageBitmap(new Blob([data],{type:'image/png'}));
      const canvas=new OffscreenCanvas(img.width,img.height);
      const ctx=canvas.getContext('2d');ctx.drawImage(img,0,0);
      return Array.from(ctx.getImageData(16,300,1,1).data);
    },intro.toString('base64'));
    if(pixel.slice(0,3).join(',')!=='243,245,237')throw new Error('No se abrió la ventana del minijuego desde la puerta');
    console.log('PASS navegador: invitado camina a cafetería y E abre el minijuego real');
    await page.mouse.click(594,342);
    await page.waitForTimeout(700);
    await page.screenshot({path:'docs/minigames/web-playing.png'});
    const audioLevel = () => Math.max(0, ...window.__coffeeAudio.map(a => {
      const samples = new Float32Array(a.fftSize); a.getFloatTimeDomainData(samples);
      return samples.reduce((sum,x)=>sum+x*x,0)/samples.length;
    }));
    await page.waitForFunction(audioLevel, null, {timeout:5000});
    await page.mouse.click(785,55);
    await page.waitForTimeout(500);
    if(await page.evaluate(audioLevel)>0.000001)throw new Error('Silenciar música no detuvo el audio');
    await page.mouse.click(785,55);
    await page.waitForFunction(audioLevel, null, {timeout:5000});
    console.log('PASS navegador: música original audible y botón para silenciar/restaurar');
    async function inspect({kind=-1,x=0,y=0}) {
      const png=await page.screenshot();
      return page.evaluate(async ({b64,kind,x,y})=>{
        const bytes=Uint8Array.from(atob(b64),c=>c.charCodeAt(0));
        const img=await createImageBitmap(new Blob([bytes],{type:'image/png'}));
        const canvas=new OffscreenCanvas(img.width,img.height);
        const ctx=canvas.getContext('2d');ctx.drawImage(img,0,0);
        if(kind<0)return Array.from(ctx.getImageData(x,y,1,1).data);
        const data=ctx.getImageData(0,0,img.width,img.height).data;
        const middle=256+(kind+0.5)*169.5;
        for(let row=110;row<510;row++) {
          let sum=0,count=0;
          for(let col=Math.round(middle-52);col<=Math.round(middle+52);col++) {
            const at=(row*img.width+col)*4;
            if(Math.abs(data[at]-245)<2 && Math.abs(data[at+1]-240)<2 && Math.abs(data[at+2]-219)<2){sum+=col;count++;}
          }
          if(count>=45)return {x:sum/count,y:row+50};
        }
        return null;
      },{b64:png.toString('base64'),kind,x,y});
    }
    async function pick(kind) {
      const deadline=Date.now()+6000;
      while(Date.now()<deadline) {
        const target=await inspect({kind});
        if(target){await page.mouse.click(target.x,target.y);await page.waitForTimeout(120);return;}
        await page.waitForTimeout(100);
      }
      throw new Error('No apareció un ingrediente clicable del tipo '+kind);
    }
    for(let i=0;i<3;i++)await pick(0);
    let color=await inspect({x:40,y:310});
    if(Math.abs(color[0]-194)>3 || Math.abs(color[1]-224)>3)throw new Error('Tres clics de café no completaron el contador');
    console.log('PASS navegador: tres granos recogidos con clics sobre ingredientes en caída');
    const scoreBefore=await page.screenshot({clip:{x:30,y:188,width:210,height:35}});
    for(let i=0;i<2;i++)await pick(1);
    const scoreAfter=await page.screenshot({clip:{x:30,y:188,width:210,height:35}});
    if(scoreBefore.equals(scoreAfter))throw new Error('Dos clics de leche no sirvieron la bebida ni aumentaron puntos');
    await page.screenshot({path:'docs/minigames/web-served.png'});
    console.log('PASS navegador: dos leches completan la receta y la bebida se sirve automáticamente');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    await page.screenshot({path:'docs/minigames/web-return.png'});
    if(process.argv.includes('--rewards')) {
      const crypto=require('crypto');
      const username='cfui_'+crypto.randomBytes(6).toString('hex');
      const password=crypto.randomBytes(16).toString('hex');
      const origin=new URL(page.url()).origin;
      const registered=await page.request.post(origin+'/auth/register',{data:{username,password}});
      if(registered.status()!==201)throw new Error('No se pudo crear cuenta temporal de recompensa');
      const account=await registered.json();
      fs.writeFileSync('.tools/coffee-ui-test.json',JSON.stringify({player_id:account.jugador.id,username}));
      await page.reload();
      await page.waitForFunction(()=>!document.getElementById('status'),null,{timeout:60000});
      await page.waitForTimeout(700);
      await page.keyboard.press('Enter');
      await page.waitForTimeout(300);
      await page.keyboard.type(username);
      await page.keyboard.press('Tab');
      await page.keyboard.type(password);
      const login=page.waitForResponse(r=>r.url().endsWith('/auth/login'));
      await page.keyboard.press('Enter');
      const logged=await login;
      if(logged.status()!==200)throw new Error('Login de prueba falló');
      const session=await logged.json();
      await page.waitForTimeout(500);
      await page.mouse.click(192,367);
      await page.waitForTimeout(6500);
      await page.keyboard.press('e');
      await page.waitForTimeout(300);
      const started=page.waitForResponse(r=>r.url().endsWith('/minijuegos/cafe') && r.request().method()==='POST');
      await page.mouse.click(594,342);
      const startResponse=await started;
      if(startResponse.status()!==201)throw new Error('La interfaz no inició la partida en el servidor');
      const livePlan=await startResponse.json();
      const originTick=Date.now();
      let completed=false;
      const finished=page.waitForResponse(r=>r.url().endsWith('/finalizar'),{timeout:80000}).then(r=>{completed=true;return r;});
      const deadline=Date.now()+70000;
      console.log('PASS navegador: cuenta autenticada inicia partida remunerada real');
      let nextProgress=Date.now()+15000;
      const distance = at => [42,56,70,86].reduce((sum,speed,i)=>sum+speed*(i===3?Math.max(0,at-45000):Math.max(0,Math.min(15000,at-i*15000))),0);
      // Use the publicly returned spawn schedule, avoiding slow screenshot
      // readbacks that can miss moving targets on software-rendered CI.
      for(const drop of livePlan.drops) {
        const due=drop.at_ms+1000;
        if(due>=60000 || completed)break;
        await page.waitForTimeout(Math.max(0,originTick+due-Date.now()));
        if(completed)break;
        const at=Date.now()-originTick;
        const x=256+(drop.kind+0.5)*169.5;
        const y=79+30+(distance(at)-distance(drop.at_ms))/1000+40;
        await page.mouse.click(x,y);
        if(Date.now()>nextProgress){console.log('PASS turno remunerado en curso con clics reales');nextProgress+=15000;}
      }
      const finishResponse=await finished;
      if(finishResponse.status()!==200)throw new Error('El cliente no pudo guardar la recompensa');
      const result=await finishResponse.json();
      if(result.coins<=0 || result.balance!==100+result.coins)throw new Error('Premio o saldo incorrecto: '+JSON.stringify(result));
      await page.waitForTimeout(400);
      await page.screenshot({path:'docs/minigames/web-reward.png'});
      const again=await page.request.post(finishResponse.url(),{headers:{Authorization:'Bearer '+session.token},data:finishResponse.request().postDataJSON()});
      if(again.status()!==200 || (await again.json()).balance!==result.balance)throw new Error('Reintentar duplicó monedas');
      const wallet=await page.request.get(origin+'/auth/session',{headers:{Authorization:'Bearer '+session.token}});
      if((await wallet.json()).jugador.monedas!==result.balance)throw new Error('No persistió el saldo');
      console.log('PASS interfaz real: '+result.score+' puntos, '+result.coins+' monedas, saldo '+result.balance+'; reintento sin duplicar');
    }
    if(errors.length)throw new Error(errors.join('\n'));
    console.log('COFFEE_WEB_VALIDATION failures=0');
  } finally {
    await browser.close();
    if(fs.existsSync('.tools/coffee-ui-test.json') && process.env.COFFEE_TEST_SKIP_CLEANUP!=='1') {
      require('child_process').execFileSync('python3',['tools/cleanup_coffee_ui.py'],{stdio:'inherit'});
    }
  }
})().catch(e=>{console.error(e);process.exit(1);});
