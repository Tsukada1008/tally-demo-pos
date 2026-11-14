"use client";

import {Download,Share2,X} from "lucide-react";
import {useEffect,useState} from "react";
import "./pwa.css";

interface InstallPromptEvent extends Event{
  prompt:()=>Promise<void>;
  userChoice:Promise<{outcome:"accepted"|"dismissed"}>;
}

export default function PwaInstall(){
  const [prompt,setPrompt]=useState<InstallPromptEvent|null>(null);
  const [ios,setIos]=useState(false);
  const [hidden,setHidden]=useState(true);

  useEffect(()=>{
    if("serviceWorker" in navigator){
      navigator.serviceWorker.register("/sw.js").catch(console.error);
    }
    const standalone=window.matchMedia("(display-mode: standalone)").matches||
      ("standalone" in navigator&&(navigator as Navigator&{standalone?:boolean}).standalone===true);
    if(standalone)return;

    const isIos=/iphone|ipad|ipod/i.test(navigator.userAgent);
    if(isIos){setIos(true);setHidden(sessionStorage.getItem("tally-install-hidden")==="1");}

    const beforeInstall=(event:Event)=>{
      event.preventDefault();
      setPrompt(event as InstallPromptEvent);
      setHidden(false);
    };
    const installed=()=>{setPrompt(null);setHidden(true)};
    window.addEventListener("beforeinstallprompt",beforeInstall);
    window.addEventListener("appinstalled",installed);
    return()=>{
      window.removeEventListener("beforeinstallprompt",beforeInstall);
      window.removeEventListener("appinstalled",installed);
    };
  },[]);

  if(hidden||(!prompt&&!ios))return null;
  const close=()=>{setHidden(true);sessionStorage.setItem("tally-install-hidden","1")};
  const install=async()=>{
    if(!prompt)return;
    await prompt.prompt();
    const result=await prompt.userChoice;
    if(result.outcome==="accepted"){setPrompt(null);setHidden(true)}
  };

  return <aside className="pwa-install" role="status">
    <button className="pwa-install-close" aria-label="インストール案内を閉じる" onClick={close}><X/></button>
    <div className="pwa-install-icon">{ios?<Share2/>:<Download/>}</div>
    <div><b>Tallyをアプリとして使用</b>{ios?<span>共有ボタンから「ホーム画面に追加」を選択してください</span>:<span>ホーム画面からすぐに起動できます</span>}</div>
    {prompt&&<button className="pwa-install-action" onClick={install}>インストール</button>}
  </aside>;
}
