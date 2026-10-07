'use strict';
const pages=['today','reward','pet'];
function showPage(name){
  if(!pages.includes(name)) return;
  for(const page of pages)document.getElementById(page).hidden=page!==name;
  for(const button of document.querySelectorAll('[data-page]'))button.setAttribute('aria-pressed',String(button.dataset.page===name));
  history.replaceState(null,'','#'+name);
}
for(const button of document.querySelectorAll('[data-page]'))button.addEventListener('click',()=>showPage(button.dataset.page));
document.querySelector('.wordmark').addEventListener('click',event=>{event.preventDefault();showPage('today');});
document.getElementById('font-toggle').addEventListener('click',event=>{const enabled=document.body.classList.toggle('large-type');event.currentTarget.setAttribute('aria-pressed',String(enabled));});
document.getElementById('theme-toggle').addEventListener('click',event=>{const enabled=document.body.dataset.theme!=='dark';document.body.dataset.theme=enabled?'dark':'light';event.currentTarget.setAttribute('aria-pressed',String(enabled));});
const states={
  ordinary:{title:'完成啦！',copy:'这次的努力，已经记下了。',speech:'一页一页读完了，\n你认真起来的样子真酷！',stamp:'CLEAR!',coin:'+5',note:'收获来自这次完成。'},
  autonomous:{title:'自己完成，真厉害！',copy:'没等提醒，你就自己开始了。',speech:'自己迈出的这一步，\n值得一个大大的赞！',stamp:'BONUS!',coin:'+8',note:'含自主奖励 3 金币。'},
  zero:{title:'完成啦！',copy:'你又认真完成了一件事。',speech:'今天的你，\n又认真完成了一件事！',stamp:'CLEAR!',coin:'+0',note:'这次没有设置 XP 或金币奖励。'},
  waiting:{title:'交给家长啦！',copy:'提交已经保存，等家长来确认。',speech:'努力已经记下了。\n我们等家长来看看！',stamp:'SENT!',coin:'+0',note:'等待确认，还没有到账。'}
};
function updateReward(){
 const state=document.getElementById('reward-state').value,data=states[state];
 document.getElementById('reward-title').textContent=state==='waiting'?'努力，已经记下了。':'做到了，真棒！';
 document.getElementById('receipt-title').textContent=data.title;document.getElementById('receipt-copy').textContent=data.copy;
 document.getElementById('reward-speech').textContent=data.speech;document.getElementById('reward-speech').style.whiteSpace='pre-line';
 document.querySelector('.clear-stamp').textContent=data.stamp;document.getElementById('receipt-note').textContent=data.note;
 document.getElementById('coin-amount').replaceChildren(document.createTextNode(data.coin+' '),Object.assign(document.createElement('small'),{textContent:'金币'}));
 document.getElementById('reward-values').hidden=state==='zero'||state==='waiting';document.getElementById('quiet-reward').hidden=state!=='zero';document.getElementById('autonomy').hidden=state!=='autonomous';
 document.querySelector('.reward-dog').alt=state==='waiting'?'小麦陪你等待家长确认':'小麦陪你庆祝完成任务';
}
document.getElementById('reward-state').addEventListener('change',updateReward);
document.getElementById('start-task').addEventListener('click',()=>{document.getElementById('reward-state').value='ordinary';updateReward();showPage('reward');});
document.getElementById('continue').addEventListener('click',()=>showPage('today'));
document.getElementById('call-dog').addEventListener('click',()=>{document.getElementById('pet-speech').textContent='汪！听见啦，\n我就在这里。';document.getElementById('pet-speech').style.whiteSpace='pre-line';});
const dialog=document.getElementById('notice');
function showNotice(title,copy){document.getElementById('notice-title').textContent=title;document.getElementById('notice-copy').textContent=copy;dialog.showModal();}
document.getElementById('parent-button').addEventListener('click',()=>showNotice('家长空间','正式应用保留现有 PIN 验证和管理页面。本样稿只展示儿童视觉方向。'));
for(const button of document.querySelectorAll('[data-demo-task]'))button.addEventListener('click',()=>showNotice(button.dataset.demoTask,'这里展示任务卡的视觉与点击区域。正式应用继续进入现有任务执行页。'));
document.getElementById('notice-close').addEventListener('click',()=>dialog.close());
showPage(pages.includes(location.hash.slice(1))?location.hash.slice(1):'today');
