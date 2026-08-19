"use client";

import { useEffect, useMemo, useState } from "react";
import { Armchair, BarChart3, BookOpen, CheckCircle2, ChevronDown, ChevronLeft, ChevronUp, CircleUserRound, ClipboardList, Clock3, CreditCard, ImageUp, KeyRound, LockKeyhole, Minus, Plus, QrCode, ReceiptText, Search, Settings, ShieldCheck, Sparkles, Timer, Trash2, UsersRound, WalletCards, X } from "lucide-react";
import { createClient as createSupabaseClient } from "../lib/supabase/client";
import { closeAdminSession, completePosSale, deletePosCheck, hasValidAdminSession, hasValidPosSession, loadPosDashboard, loadPosReceivables, moveOpenCheck, openAdminSession, openPosSession, PosDashboard, PosReceivable, saveOpenCheck, settlePosReceivable, toggleAttendance, toggleBreak, updateDiscountPresets, updatePayrollRounding, updatePosCatalog, updateStorePin } from "../lib/store-security";
import Checkout from "./Checkout";
import {CheckDetailModal,HistoryView as HistoryDataView,ReportsView as ReportsDataView} from "./DashboardViews";

type Tab = "tables" | "orders" | "timecard" | "history" | "reports" | "settings";
type Item = { id: number|string; name: string; category: string; price: number; color: string; staffDrink?:boolean; backAmount?:number };
type Line = Item & { qty: number; staff?: string };
type Table = { id: number|string; name: string; guest?: string; people?: number; total?: number; started?: string; checkId?:string; memo?:string; lines?:Line[] };

const yen = (n: number) => `¥${n.toLocaleString("ja-JP")}`;
const APP_NAME = process.env.NEXT_PUBLIC_APP_ENV === "demo" ? "Tally" : "TIPSY";
const APP_ENV = process.env.NEXT_PUBLIC_APP_ENV; // "demo" | "sample" | undefined (production)
const EnvBadge = () => APP_ENV === "demo" ? <span className="demo-badge">DEMO</span> : APP_ENV === "sample" ? <span className="demo-badge sample">サンプル</span> : null;
const products: Item[] = [
  { id: 1, name: "生ビール", category: "ビール", price: 700, color: "yellow" },
  { id: 2, name: "瓶ビール", category: "ビール", price: 800, color: "yellow" },
  { id: 3, name: "ハイボール", category: "ウイスキー", price: 800, color: "brown" },
  { id: 4, name: "山崎 ハイボール", category: "ウイスキー", price: 1200, color: "brown" },
  { id: 5, name: "レモンサワー", category: "焼酎", price: 700, color: "blue" },
  { id: 6, name: "ウーロンハイ", category: "焼酎", price: 700, color: "blue" },
  { id: 7, name: "ジントニック", category: "カクテル", price: 900, color: "pink" },
  { id: 8, name: "カシスオレンジ", category: "カクテル", price: 900, color: "pink" },
  { id: 9, name: "お通し", category: "セット料金", price: 500, color: "purple" },
  { id: 10, name: "ミックスナッツ", category: "フード", price: 600, color: "orange" }
];
const tables: Table[] = [
  { id: 1, name: "A卓", guest: "山田様", people: 3, total: 12500, started: "21:14" },
  { id: 2, name: "B卓", guest: "佐々木様", people: 2, total: 6800, started: "22:02" },
  { id: 3, name: "C卓" },
  { id: 4, name: "D卓", guest: "加藤様", people: 4, total: 18200, started: "20:48" },
  { id: 5, name: "カウンター 1", guest: "鈴木様", people: 1, total: 2400, started: "22:36" },
  { id: 6, name: "カウンター 2" },
  { id: 7, name: "カウンター 3" },
  { id: 8, name: "個室", guest: "中村様", people: 5, total: 23100, started: "20:31" }
];

export default function Page() {
  const [posAccess,setPosAccess]=useState<"loading"|"locked"|"ready">("loading");
  const [dashboard,setDashboard]=useState<PosDashboard|null>(null);
  const [receivables,setReceivables]=useState<PosReceivable[]>([]);
  const [tab, setTab] = useState<Tab>("tables");
  const [selected, setSelected] = useState<Table | null>(null);
  const [category, setCategory] = useState("");
  const [lines, setLines] = useState<Line[]>([]);
  const [checkout, setCheckout] = useState(false);
  const [pay, setPay] = useState("現金");
  const [ownerOpen, setOwnerOpen] = useState(false);
  const [ownerTarget, setOwnerTarget] = useState<Tab>("reports");
  const [newCheckOpen, setNewCheckOpen] = useState(false);
  const [adminLoggedIn,setAdminLoggedIn]=useState(false);
  const [paymentQr, setPaymentQr] = useState("");
  const [staffDrinkOpen,setStaffDrinkOpen]=useState<Item|null>(null);
  const [tableInfoOpen,setTableInfoOpen]=useState(false);
  useEffect(()=>{
    setPaymentQr(localStorage.getItem("tipsy-payment-qr")||"");
    if(Number(localStorage.getItem("tipsy-admin-until")||0)>Date.now())hasValidAdminSession().then(setAdminLoggedIn);else closeAdminSession();
    if(location.hash.includes("error=")||location.search.includes("error=")){
      location.replace("/auth/error"); return;
    }
    if(location.hash.includes("access_token")&&location.hash.includes("type=invite")){
      createSupabaseClient().auth.getSession().then(({data})=>{if(data.session)location.replace("/auth/update-password")});
    }
    hasValidPosSession().then(valid=>setPosAccess(valid?"ready":"locked")).catch(()=>setPosAccess("locked"));
  },[]);
  useEffect(()=>{const timer=window.setInterval(()=>{if(adminLoggedIn&&Number(localStorage.getItem("tipsy-admin-until")||0)<=Date.now())adminLogout()},30000);return()=>window.clearInterval(timer)},[adminLoggedIn]);
  const adminLogin=()=>{const minutes=Math.max(5,Number(localStorage.getItem("tipsy-setting-自動ログアウト")||60));localStorage.setItem("tipsy-admin-until",String(Date.now()+minutes*60000));setAdminLoggedIn(true)};
  const adminLogout=()=>{localStorage.removeItem("tipsy-admin-until");closeAdminSession();setAdminLoggedIn(false);setTab("tables")};
  const savePaymentQr=(data:string)=>{setPaymentQr(data);if(data)localStorage.setItem("tipsy-payment-qr",data);else localStorage.removeItem("tipsy-payment-qr")};
  const handleToggleAttendance=async(name:string)=>{await toggleAttendance(name);setDashboard(await loadPosDashboard())};
  const handleToggleBreak=async(name:string)=>{await toggleBreak(name);setDashboard(await loadPosDashboard())};
  const subtotal = useMemo(() => lines.reduce((s, l) => s + l.price * l.qty, 0), [lines]);
  const add = (item: Item) => setLines(curr => curr.some(l => l.id === item.id && !l.staff) ? curr.map(l => l.id === item.id && !l.staff ? { ...l, qty: l.qty + 1 } : l) : [...curr, { ...item, qty: 1 }]);
  const addStaffDrink = (staff:string,drink:Item) => setLines(curr=>{const found=curr.find(l=>l.name===drink.name&&l.staff===staff&&l.price===drink.price&&l.backAmount===drink.backAmount);return found?curr.map(l=>l===found?{...l,qty:l.qty+1}:l):[...curr,{...drink,id:`${drink.id}-${staff}`,color:"red",qty:1,staff}]});
  const change = (id: number|string, delta: number, staff?: string) => setLines(curr => curr.map(l => l.id === id && l.staff === staff ? { ...l, qty: l.qty + delta } : l).filter(l => l.qty > 0));

  useEffect(()=>{if(posAccess==="ready"){loadPosDashboard().then(setDashboard).catch(console.error);loadPosReceivables().then(setReceivables).catch(console.error)}},[posAccess]);
  useEffect(()=>{const first=dashboard?.categories[0]?.name;if(first&&!dashboard?.categories.some(c=>c.name===category))setCategory(first)},[dashboard,category]);
  useEffect(()=>{
    if(!selected||posAccess!=="ready"||checkout)return;
    const timer=window.setTimeout(()=>saveOpenCheck({tableName:selected.name,customerName:selected.guest||"",guestCount:selected.people||1,lines:lines.map(({name,category,price,qty,staff,backAmount})=>({name,category,price,qty,staff,backAmount})),memo:selected.memo}).then(()=>loadPosDashboard()).then(setDashboard).catch(console.error),500);
    return()=>window.clearTimeout(timer);
  },[selected,lines,posAccess,checkout]);
  const liveProducts:Item[]=dashboard?.products?.length?dashboard.products.map(p=>({...p,id:p.id,color:p.color})):products;
  const liveTables:Table[]=dashboard?.tables?.length?dashboard.tables.map(t=>({...t,lines:t.lines?.map((l,i)=>({...l,id:`${t.id}-${i}`,color:dashboard.categories.find(c=>c.name===l.category)?.color||"#ff2f8f"}))})):tables;

  if(posAccess!=="ready") return <StaffAccessScreen loading={posAccess==="loading"} enter={async pin=>{const valid=await openPosSession(pin);if(valid)setPosAccess("ready");return valid}}/>;
  if (selected) return <><OrderScreen table={selected} products={liveProducts} categories={dashboard?.categories||[]} category={category} setCategory={setCategory} lines={lines} add={add} openStaffDrink={drink=>setStaffDrinkOpen(drink)} change={change} subtotal={subtotal} back={() => setSelected(null)} edit={()=>setTableInfoOpen(true)} checkout={() => setCheckout(true)} />{tableInfoOpen&&<TableInfoModal table={selected} tables={liveTables.filter(t=>t.id===selected.id||(!t.checkId&&!t.guest))} close={()=>setTableInfoOpen(false)} start={async(table,guest,people,memo)=>{if(selected.checkId&&table.id!==selected.id)await moveOpenCheck(String(selected.checkId),table.name);setSelected({...selected,id:table.id,name:table.name,guest:guest||undefined,people,memo});setTableInfoOpen(false)}}/>}{staffDrinkOpen&&<StaffDrinkModal staff={(dashboard?.onShift||[]).map((shift,i)=>({id:`${shift.staffName}-${i}`,name:shift.staffName}))} drinks={staffDrinkOpen.id==="staff-drink-menu"?liveProducts.filter(p=>p.staffDrink):[staffDrinkOpen]} close={()=>setStaffDrinkOpen(null)} add={(staff,drink)=>{addStaffDrink(staff,drink);setStaffDrinkOpen(null)}}/>}{checkout && <Checkout total={subtotal} pay={pay} setPay={setPay} qr={paymentQr} discounts={dashboard?.discounts||[]} close={() => setCheckout(false)} save={async details=>{const method=pay==="現金"?"cash":pay==="QR"?"qr":pay==="売掛"?"receivable":"other";return completePosSale({tableName:selected.name,customerName:selected.guest||"",guestCount:selected.people||1,lines:lines.map(({name,category,price,qty,staff,backAmount})=>({name,category,price,qty,staff,backAmount})),method,receivedAmount:details.received,debtorName:details.debtorName,receivableMemo:details.memo,dueDate:details.dueDate,discountName:details.discountName,discountAmount:details.discountAmount})}} finish={()=>{setCheckout(false);setSelected(null);setLines([]);loadPosDashboard().then(setDashboard)}}/>}</>;

  return <main className="app-shell">
    <header className="topbar">
      <div className="brand"><div className="brand-mark"><span>T</span></div><div><b>{APP_NAME}<EnvBadge/></b><small>BAR &amp; RESTAURANT · CHECK SYSTEM</small></div></div>
      <div className="top-actions"><div className="business-date"><Clock3 size={15}/><span>営業日</span><b>{dashboard?.businessDate||"--"}</b></div><button className={`owner-button ${adminLoggedIn?"logged-in":""}`} aria-label={adminLoggedIn?"Administratorログアウト":"Administratorログイン"} title={adminLoggedIn?"Administratorログアウト":"Administratorログイン"} onClick={()=>adminLoggedIn?adminLogout():(setOwnerTarget("tables"),setOwnerOpen(true))}>{adminLoggedIn?<><ShieldCheck size={17}/><span>ログアウト</span></>:<><LockKeyhole size={17}/><span>Administratorログイン</span></>}</button></div>
    </header>
    <section className="content">
      {tab === "tables" && <TablesView tables={liveTables} receivables={receivables} onSettle={async(id,method)=>{await settlePosReceivable(id,method);setReceivables(await loadPosReceivables());setDashboard(await loadPosDashboard())}} admin={adminLoggedIn} onDelete={async id=>{await deletePosCheck(id);setDashboard(await loadPosDashboard())}} onCreate={()=>setNewCheckOpen(true)} onSelect={t => {setLines((t.lines||[]).map((l,i)=>({...l,id:l.id||`${t.id}-${i}`,color:liveProducts.find(p=>p.category===l.category)?.color||"#ff2f8f"})));setSelected(t)}}/>} 
      {tab === "timecard" && <TimecardView staff={dashboard?.staff||[]} onShift={dashboard?.onShift||[]} toggle={handleToggleAttendance} toggleBreak={handleToggleBreak}/>}
      {tab === "history" && <HistoryDataView dashboard={dashboard} admin={adminLoggedIn} onDelete={async id=>{await deletePosCheck(id);setDashboard(await loadPosDashboard())}}/>}
      {tab === "reports" && <ReportsDataView dashboard={dashboard}/>}
      {tab === "settings" && <SettingsView paymentQr={paymentQr} savePaymentQr={savePaymentQr} dashboard={dashboard} refresh={()=>loadPosDashboard().then(setDashboard)}/>}
    </section>
    <nav className="bottom-nav">
      <NavButton active={tab === "tables"} icon={<Armchair/>} label="ホーム" onClick={() => setTab("tables")}/>
      <NavButton active={tab === "timecard"} icon={<Timer/>} label="タイムカード" onClick={() => setTab("timecard")}/>
      <NavButton active={tab === "history"} icon={<ReceiptText/>} label="会計履歴" onClick={() => setTab("history")}/>
      <NavButton active={tab === "reports"} icon={<BarChart3/>} label="集計" lock={!adminLoggedIn} onClick={() => {if(adminLoggedIn)setTab("reports");else{setOwnerTarget("reports");setOwnerOpen(true)}}}/>
      <NavButton active={tab === "settings"} icon={<Settings/>} label="設定" lock={!adminLoggedIn} onClick={() => {if(adminLoggedIn)setTab("settings");else{setOwnerTarget("settings");setOwnerOpen(true)}}}/>
    </nav>
    {ownerOpen && <OwnerModal close={() => setOwnerOpen(false)} enter={async pin => {const minutes=Math.max(5,Number(localStorage.getItem("tipsy-setting-自動ログアウト")||60));const valid=await openAdminSession(pin,minutes);if(valid){adminLogin();setOwnerOpen(false);if(ownerTarget!=="tables")setTab(ownerTarget)}return valid}}/>}
    {newCheckOpen&&<NewCheckModal tables={liveTables.filter(t=>!t.checkId&&!t.guest)} close={()=>setNewCheckOpen(false)} start={(table,guest,people,memo)=>{const opened={...table,guest:guest||undefined,people,memo,lines:[]};setLines([]);setSelected(opened);setNewCheckOpen(false);saveOpenCheck({tableName:table.name,customerName:guest,guestCount:people,memo,lines:[]}).then(()=>loadPosDashboard()).then(setDashboard).catch(console.error)}}/>}
  </main>;
}

function StaffAccessScreen({loading,enter}:{loading:boolean;enter:(pin:string)=>Promise<boolean>}){
  const [pin,setPin]=useState("");const [checking,setChecking]=useState(false);const [error,setError]=useState("");
  const submit=async()=>{if(pin.length!==4||checking)return;setChecking(true);setError("");try{if(!await enter(pin)){setPin("");setError("PINが違います")}}catch{setError("店舗データに接続できませんでした")}finally{setChecking(false)}};
  return <main className="auth-page"><section className="auth-card"><div className="auth-icon"><KeyRound/></div><span>STORE DEVICE</span><h1>{APP_NAME} 店舗端末<EnvBadge/></h1>{loading?<p>端末を確認しています…</p>:<><p>最初の利用時だけ、従業員用PINを入力してください。30日間この端末を記憶します。</p><input aria-label="従業員用PIN" inputMode="numeric" type="password" maxLength={4} value={pin} onChange={e=>setPin(e.target.value.replace(/\D/g,""))} onKeyDown={e=>{if(e.key==="Enter")submit()}} placeholder="4桁のPIN" autoFocus/>{error&&<div className="auth-error">{error}</div>}<button type="button" disabled={pin.length!==4||checking} onClick={submit}>{checking?"確認しています…":"店舗画面を開く"}</button></>}</section></main>
}

function TablesView({tables,receivables,admin,onSelect,onCreate,onDelete,onSettle}:{tables:Table[];receivables:PosReceivable[];admin:boolean;onSelect:(t:Table)=>void;onCreate:()=>void;onDelete:(id:string)=>Promise<void>;onSettle:(id:string,method:"cash"|"qr"|"other")=>Promise<void>}) {
  const occupied=tables.filter(t=>t.checkId||t.guest);const guests=occupied.reduce((s,t)=>s+(t.people||0),0);const unpaid=occupied.reduce((s,t)=>s+(t.total||0),0);
  const [openReceivableCheck,setOpenReceivableCheck]=useState<string|null>(null);
  const [settling,setSettling]=useState<PosReceivable|null>(null);const [settleMethod,setSettleMethod]=useState<"cash"|"qr"|"other">("cash");const [settleBusy,setSettleBusy]=useState(false);const [settleError,setSettleError]=useState("");
  const settle=async()=>{if(!settling||settleBusy)return;setSettleBusy(true);setSettleError("");try{await onSettle(settling.id,settleMethod);setSettling(null)}catch{setSettleError("入金処理に失敗しました。もう一度お試しください。")}finally{setSettleBusy(false)}};
  return <><div className="page-heading"><div><span className="eyebrow">{APP_NAME} HOME</span><h1>ホーム</h1><p>使用中の伝票を確認できます</p></div><button className="create-check-button" onClick={onCreate}><Plus/>伝票を作成</button></div><div className="stat-row home-stats"><div><span className="dot live"/>使用中 <b>{occupied.length}</b><small>卓</small></div><div><UsersRound size={17}/>在店 <b>{guests}</b><small>名</small></div><div><WalletCards size={17}/>未会計 <b>{yen(unpaid)}</b></div></div>
  {occupied.length?<div className="table-grid occupied-only">{occupied.map(t=><div key={t.id} className="table-card occupied" role="button" tabIndex={0} onClick={()=>onSelect(t)} onKeyDown={e=>{if(e.key==="Enter")onSelect(t)}}><div className="card-top"><span className="table-name">{t.name}</span><span className="status"><i/>使用中</span></div><div className="guest"><CircleUserRound/><div><b>{t.guest||"お名前未入力"}</b><span>{t.people}名</span></div></div><div className="card-bottom"><div><small>現在金額</small><strong>{yen(t.total||0)}</strong></div><div className="open-slip"><BookOpen size={16}/>伝票を開く</div></div>{admin&&t.checkId&&<button className="admin-delete card-delete" onClick={async e=>{e.stopPropagation();if(!confirm(`${t.name}の未会計伝票を削除しますか？`))return;try{await onDelete(t.checkId!)}catch{alert("削除できませんでした。Administratorログインの有効期限を確認して、もう一度お試しください。")}}}><Trash2/>伝票削除</button>}</div>)}</div>:<div className="empty-home"><ClipboardList/><b>使用中の伝票はありません</b><button onClick={onCreate}><Plus/>最初の伝票を作成</button></div>}
  <div className="receivable-section"><div className="report-section-head"><h2 className="settings-section-title">売掛</h2><span>{receivables.length}件</span></div><div className="list-panel receivable-list">{receivables.length?receivables.map(x=><div className="history-row receivable-detail-row" role="button" tabIndex={0} key={x.id} onClick={()=>setOpenReceivableCheck(x.checkId)} onKeyDown={e=>{if(e.key==="Enter")setOpenReceivableCheck(x.checkId)}}><div className="round-icon"><BookOpen/></div><div><b>#{String(x.number).padStart(4,"0")}　{x.debtorName||x.table||"売掛先未入力"}</b><span>{new Date(x.createdAt).toLocaleString("ja-JP")}・{x.table||"卓なし"}{x.dueDate?`・期限 ${x.dueDate}`:""}</span></div><strong>{yen(x.amount)}</strong><button className="receivable-settle-button" onClick={e=>{e.stopPropagation();setSettling(x);setSettleMethod("cash");setSettleError("")}}>入金処理</button></div>):<div className="history-row"><div><b>売掛はありません</b><span>売掛で会計した伝票はここに残ります</span></div></div>}</div></div>
  {openReceivableCheck&&<CheckDetailModal checkId={openReceivableCheck} close={()=>setOpenReceivableCheck(null)}/>} 
  {settling&&<div className="modal-backdrop"><div className="table-info-modal receivable-settle-modal"><button className="modal-x" onClick={()=>setSettling(null)}><X/></button><span className="eyebrow">RECEIVABLE PAYMENT</span><h2>売掛の入金処理</h2><div className="selected-table"><BookOpen/><div><small>#{String(settling.number).padStart(4,"0")}・{settling.table||"卓なし"}</small><b>{settling.debtorName}</b></div></div><div className="checkout-total"><span>入金額</span><strong>{yen(settling.amount)}</strong></div><h3>入金方法</h3><div className="receivable-payment-methods"><button className={settleMethod==="cash"?"active":""} onClick={()=>setSettleMethod("cash")}>現金</button><button className={settleMethod==="qr"?"active":""} onClick={()=>setSettleMethod("qr")}>QR</button><button className={settleMethod==="other"?"active":""} onClick={()=>setSettleMethod("other")}>その他</button></div>{settleError&&<div className="auth-error">{settleError}</div>}<button className="complete" disabled={settleBusy} onClick={settle}>{settleBusy?"処理しています…":"入金を確定する"}</button></div></div>}</>;
}

function OrderScreen({table,products,categories,category,setCategory,lines,add,openStaffDrink,change,subtotal,back,edit,checkout}:{table:Table;products:Item[];categories:Array<{id:string;name:string;color:string}>;category:string;setCategory:(s:string)=>void;lines:Line[];add:(i:Item)=>void;openStaffDrink:(drink:Item)=>void;change:(id:number|string,d:number,s?:string)=>void;subtotal:number;back:()=>void;edit:()=>void;checkout:()=>void}) {
  const [manualName,setManualName]=useState("");const [manualPrice,setManualPrice]=useState("");const [manualTax,setManualTax]=useState<"included"|"excluded">("included");const [manualBack,setManualBack]=useState(false);const [manualBackAmount,setManualBackAmount]=useState("");
  const cats=categories;
  const shown = products.filter(p=>p.category===category);const selectedCategory=categories.find(c=>c.name===category);
  const addManual=()=>{const rawName=manualName.trim(),basePrice=Number(manualPrice);if(!rawName||basePrice<0||category!=="その他")return;const excluded=manualTax==="excluded";const item:Item={id:`manual-${Date.now()}`,name:excluded?`${rawName}（外税）`:rawName,price:excluded?Math.floor(basePrice*1.1):basePrice,category,color:selectedCategory?.color||"#ff2f8f",staffDrink:manualBack,backAmount:manualBack?Math.max(0,Number(manualBackAmount)||0):0};if(manualBack)openStaffDrink(item);else add(item);setManualName("");setManualPrice("");setManualBackAmount("")};
  return <main className="order-page"><header className="order-head"><button className="icon-btn" onClick={back}><ChevronLeft/></button><div><b>{table.name}</b><span>{table.guest || "新規のお客様"} ・ {table.people || 1}名</span></div><button className="soft-button" onClick={edit}>卓情報を編集</button></header>
    <div className="order-layout"><section className="menu-pane"><div className="order-menu-grid"><div className="category-tabs">{cats.map(c=><button style={{"--tab-color":c.color} as React.CSSProperties} className={category===c.name?"active":""} onClick={()=>setCategory(c.name)} key={c.id}>{c.name}</button>)}</div><div className="product-area"><div className="menu-title"><div><h2>{category}</h2><span>{shown.length}商品</span></div><button className="staff-drink" onClick={()=>openStaffDrink({id:"staff-drink-menu",name:"",category:"",price:0,color:"",staffDrink:true})}><Sparkles size={17}/>キャストドリンク</button></div>{category==="その他"&&<form className="manual-product" onSubmit={e=>{e.preventDefault();addManual()}}><input aria-label="その他の商品名を手入力" value={manualName} onChange={e=>setManualName(e.target.value)} placeholder="商品名を手入力"/><div><span>¥</span><input aria-label="その他の金額を手入力" inputMode="numeric" type="number" min="0" value={manualPrice} onChange={e=>setManualPrice(e.target.value)} placeholder="金額"/></div><div className="manual-tax"><button type="button" className={manualTax==="included"?"active":""} onClick={()=>setManualTax("included")}>内税</button><button type="button" className={manualTax==="excluded"?"active":""} onClick={()=>setManualTax("excluded")}>外税</button></div><div className="manual-back-choice"><button type="button" className={!manualBack?"active":""} onClick={()=>setManualBack(false)}>バック対象外</button><button type="button" className={manualBack?"active":""} onClick={()=>setManualBack(true)}>バック対象</button></div>{manualBack&&<div className="manual-back-amount"><span>戻 ¥</span><input aria-label="バック金額" inputMode="numeric" type="number" min="0" value={manualBackAmount} onChange={e=>setManualBackAmount(e.target.value)} placeholder="金額"/></div>}<button disabled={!manualName.trim()||manualPrice===""||(manualBack&&manualBackAmount==="")} type="submit"><Plus/>追加</button></form>}<div className="product-grid">{shown.map(p=><button className="product" style={{"--cat":p.color} as React.CSSProperties} key={p.id} onClick={()=>p.staffDrink?openStaffDrink(p):add(p)}><span>{p.category}{p.staffDrink?"・バック対象":""}</span><b>{p.name}</b><strong>{yen(p.price)}</strong><i><Plus size={16}/></i></button>)}</div></div></div></section>
    <aside className="slip"><div className="slip-head"><div><ClipboardList/><h2>伝票</h2></div><span>{lines.reduce((s,l)=>s+l.qty,0)}点</span></div><div className="slip-lines">{lines.map(l=><div className="line" key={`${l.id}-${l.staff||""}`}><div className="line-color" style={{background:l.color}}/><div className="line-main"><b>{l.staff ? `${l.staff}／${l.name}` : l.name}</b><small>{yen(l.price)}</small></div><div className="stepper"><button onClick={()=>change(l.id,-1,l.staff)}>{l.qty===1?<Trash2/>:<Minus/>}</button><b>{l.qty}</b><button onClick={()=>change(l.id,1,l.staff)}><Plus/></button></div><strong>{yen(l.price*l.qty)}</strong></div>)}</div><div className="slip-total checkout-only"><div><span>小計</span><span>{yen(subtotal)}</span></div><div className="tax">消費税（内税） {yen(Math.floor(subtotal/11))}</div><div className="grand"><span>合計</span><strong>{yen(subtotal)}</strong></div><button onClick={checkout}>会計へ進む <ChevronLeft className="right"/></button></div></aside></div></main>;
}

function OrdersView({onSelect}:{onSelect:(t:Table)=>void}) { return <><div className="page-heading"><div><span className="eyebrow">OPEN CHECKS</span><h1>伝票</h1><p>未会計の伝票を一覧表示しています</p></div></div><div className="list-panel">{tables.filter(t=>t.guest).map(t=><button className="history-row" onClick={()=>onSelect(t)} key={t.id}><div className="round-icon"><ClipboardList/></div><div><b>{t.name} ・ {t.guest}</b><span>{t.people}名 / {t.started} 開始</span></div><strong>{yen(t.total!)}</strong><ChevronLeft className="right"/></button>)}</div></> }
function HistoryView() { return <><div className="page-heading"><div><span className="eyebrow">PAYMENT HISTORY</span><h1>会計履歴</h1><p>本日完了した会計</p></div><div className="search"><Search/><input placeholder="伝票番号・お客様名で検索"/></div></div><div className="list-panel">{[["#0048","カウンター 2","現金",4800,"22:18"],["#0047","B卓","QR",12600,"21:42"],["#0046","A卓","売掛",8500,"20:36"]].map(x=><div className="history-row" key={x[0] as string}><div className="round-icon"><ReceiptText/></div><div><b>{x[0]}　{x[1]}</b><span>{x[4]} ・ {x[2]}</span></div><strong>{yen(x[3] as number)}</strong></div>)}</div></> }
function ReportsView() { return <><div className="page-heading"><div><span className="eyebrow">DAILY REPORT</span><h1>本日の集計</h1><p>営業日 2026年8月4日</p></div><span className="owner-chip"><ShieldCheck/>オーナーモード</span></div><div className="report-grid"><div className="report-main"><small>総売上</small><strong>¥184,600</strong><span>昨日比 <b>+12.4%</b></span></div>{[["会計件数","18件"],["客数","42名"],["客単価","¥4,395"],["現金売上","¥98,500"],["QR売上","¥62,400"],["未回収売掛","¥23,700"]].map(x=><div className="metric" key={x[0]}><small>{x[0]}</small><b>{x[1]}</b></div>)}</div></> }
function SettingsView({paymentQr,savePaymentQr,dashboard,refresh}:{paymentQr:string;savePaymentQr:(s:string)=>void;dashboard:PosDashboard|null;refresh:()=>Promise<void>}){
  const [pinType,setPinType]=useState<"staff"|"admin"|null>(null);
  const [qrOpen,setQrOpen]=useState(false);
  const [settingOpen,setSettingOpen]=useState<string|null>(null);
  const [payrollOpen,setPayrollOpen]=useState(false);
  const roundingLabel=dashboard?.payrollRounding?`${dashboard.payrollRounding.unitMinutes}分単位・${dashboard.payrollRounding.mode==="floor"?"切り捨て":"切り上げ"}`:"未設定";
  const items=[
    ["分類","分類名、表示色、表示順を設定",<ClipboardList/>],["商品・価格","商品、分類、価格を設定",<ClipboardList/>],["卓の設定","卓名、番号、表示順を設定",<Armchair/>],
    ["従業員","氏名・時給を設定",<UsersRound/>],["値引き","通常会計で使える値引きを設定",<ReceiptText/>],
    ["店舗情報","店名、住所、領収書情報を設定",<Settings/>],["営業日","営業日の切替時刻を設定",<Clock3/>],["自動ログアウト","Administratorログインの有効時間を設定",<Clock3/>]
  ];
  return <><div className="page-heading"><div><span className="eyebrow">STORE SETTINGS</span><h1>設定</h1><p>店舗とメニューの設定を管理します</p></div><span className="owner-chip"><ShieldCheck/>Administrator</span></div>
    <h2 className="settings-section-title">決済設定</h2><div className="settings-grid payment-settings"><button onClick={()=>setQrOpen(true)}><span><QrCode/></span><div><b>支払い用QRコード</b><small>QR決済時にお客様へ表示する画像を登録</small></div><em>{paymentQr?"登録済み":"未登録"}</em><ChevronLeft className="right"/></button></div><h2 className="settings-section-title">アクセス管理</h2><div className="settings-grid pin-settings">
      <button onClick={()=>setPinType("staff")}><span><KeyRound/></span><div><b>従業員用PIN</b><small>通常画面を開くための4桁PINを設定</small></div><em>設定済み</em><ChevronLeft className="right"/></button>
      <button onClick={()=>setPinType("admin")}><span><LockKeyhole/></span><div><b>Administrator用PIN</b><small>集計・設定を開くための4桁PINを設定</small></div><em>設定済み</em><ChevronLeft className="right"/></button>
    </div><h2 className="settings-section-title">給与設定</h2><div className="settings-grid"><button onClick={()=>setPayrollOpen(true)}><span><Timer/></span><div><b>給与の端数処理</b><small>勤務時間の丸め単位と方向を設定</small></div><em>{roundingLabel}</em><ChevronLeft className="right"/></button></div>
    <h2 className="settings-section-title">店舗管理</h2><div className="settings-grid">{items.map(x=><button key={x[0] as string} onClick={()=>setSettingOpen(x[0] as string)}><span>{x[2]}</span><div><b>{x[0]}</b><small>{x[1]}</small></div><ChevronLeft className="right"/></button>)}</div>
    {pinType&&<PinSettingsModal type={pinType} close={()=>setPinType(null)} save={pin=>updateStorePin(pin,pinType)}/>} {qrOpen&&<QrSettingsModal value={paymentQr} save={savePaymentQr} close={()=>setQrOpen(false)}/>} {payrollOpen&&<PayrollRoundingModal current={dashboard?.payrollRounding} refresh={refresh} close={()=>setPayrollOpen(false)}/>} {settingOpen&&(settingOpen==="分類"||settingOpen==="商品・価格"?<CatalogSettingsModal mode={settingOpen==="分類"?"categories":"products"} dashboard={dashboard} refresh={refresh} close={()=>setSettingOpen(null)}/>:settingOpen==="値引き"?<DiscountSettingsModal dashboard={dashboard} refresh={refresh} close={()=>setSettingOpen(null)}/>:settingOpen==="卓の設定"?<TableSettingsModal dashboard={dashboard} refresh={refresh} close={()=>setSettingOpen(null)}/>:settingOpen==="従業員"?<StaffSettingsModal dashboard={dashboard} refresh={refresh} close={()=>setSettingOpen(null)}/>:<GeneralSettingsModal title={settingOpen} dashboard={dashboard} refresh={refresh} close={()=>setSettingOpen(null)}/>)}</>}

function CatalogSettingsModal({mode,dashboard,refresh,close}:{mode:"categories"|"products";dashboard:PosDashboard|null;refresh:()=>Promise<void>;close:()=>void}){
  type CategoryRow={key:string;name:string;color:string};type ProductRow={key:string;name:string;price:number;category:string;staffDrink:boolean;backAmount:number};
  const [categories,setCategories]=useState<CategoryRow[]>(()=>dashboard?.categories.map(c=>({key:c.id,name:c.name,color:c.color}))||[]);
  const [productsRows,setProductsRows]=useState<ProductRow[]>(()=>dashboard?.products.map(p=>({key:p.id,name:p.name,price:p.price,category:p.category,staffDrink:p.staffDrink||false,backAmount:p.backAmount||0}))||[]);
  const [selectedProductCategory,setSelectedProductCategory]=useState(()=>dashboard?.categories[0]?.name||"");
  const [saving,setSaving]=useState(false);const [saved,setSaved]=useState(false);const [error,setError]=useState("");
  const moveCategory=(index:number,delta:number)=>setCategories(rows=>{const next=[...rows],to=index+delta;if(to<0||to>=next.length)return rows;[next[index],next[to]]=[next[to],next[index]];return next});
  const moveProduct=(index:number,delta:number)=>setProductsRows(rows=>{const next=[...rows],to=index+delta;if(to<0||to>=next.length)return rows;[next[index],next[to]]=[next[to],next[index]];return next});
  const visibleProducts=productsRows.filter(row=>row.category===selectedProductCategory);
  const moveVisibleProduct=(rowKey:string,delta:number)=>setProductsRows(rows=>{const same=rows.filter(row=>row.category===selectedProductCategory);const index=same.findIndex(row=>row.key===rowKey);const other=same[index+delta];if(index<0||!other)return rows;const from=rows.findIndex(row=>row.key===rowKey),to=rows.findIndex(row=>row.key===other.key);const next=[...rows];[next[from],next[to]]=[next[to],next[from]];return next});
  const save=async()=>{setSaving(true);setError("");try{if(mode==="categories"){const valid=categories.filter(x=>x.name.trim());if(!valid.length)throw new Error();const categoryItems=valid.map(({name,color})=>({name:name.trim(),color}));await updatePosCatalog("categories",categoryItems);const renamed=new Map(valid.map(row=>[row.key,row.name.trim()]));const remainingProducts=(dashboard?.products||[]).flatMap(product=>{const original=dashboard?.categories.find(category=>category.name===product.category);const nextCategory=original?renamed.get(original.id):undefined;return nextCategory?[{name:product.name,price:product.price,category:nextCategory,staffDrink:product.staffDrink,backAmount:product.backAmount}]:[]});await updatePosCatalog("products",remainingProducts);await updatePosCatalog("categories",categoryItems)}else{const valid=productsRows.filter(x=>x.name.trim());if(!valid.length||valid.some(x=>x.price<0||!x.category))throw new Error();await updatePosCatalog("products",valid.map(({name,price,category,staffDrink,backAmount})=>({name:name.trim(),price,category,staffDrink,backAmount})))}await refresh();setSaved(true)}catch{setError("入力内容を確認してください。商品には価格と分類が必要です。")}finally{setSaving(false)}};
  return <div className="modal-backdrop"><div className="catalog-modal"><div className="catalog-head"><div><span className="eyebrow">CATALOG SETTINGS</span><h2>{mode==="categories"?"分類の設定":"商品・価格の設定"}</h2><p>{mode==="categories"?"伝票画面の左側に表示する分類と色を編集します。":"商品名、販売価格、分類を編集します。"}</p></div><button className="modal-x" onClick={close}><X/></button></div>
  {mode==="categories"?<div className="catalog-table"><div className="catalog-labels"><span>順番</span><span>表示色</span><span>分類名</span><span/></div>{categories.map((row,i)=><div className="catalog-row category-row" key={row.key}><div className="sort-buttons"><button disabled={i===0} onClick={()=>moveCategory(i,-1)} aria-label={`${row.name||i+1}を上へ`}><ChevronUp/></button><button disabled={i===categories.length-1} onClick={()=>moveCategory(i,1)} aria-label={`${row.name||i+1}を下へ`}><ChevronDown/></button></div><input aria-label={`${i+1}番目の表示色`} type="color" value={row.color} onChange={e=>setCategories(x=>x.map(r=>r.key===row.key?{...r,color:e.target.value}:r))}/><input aria-label={`${i+1}番目の分類名`} value={row.name} onChange={e=>setCategories(x=>x.map(r=>r.key===row.key?{...r,name:e.target.value}:r))} placeholder="例：ビール"/><button className="row-delete" onClick={()=>setCategories(x=>x.filter(r=>r.key!==row.key))}><Trash2/></button></div>)}<button className="add-row" onClick={()=>setCategories(x=>[...x,{key:`new-${Date.now()}`,name:"",color:"#6b7280"}])}><Plus/>分類を追加</button></div>
  :<div className="catalog-products-layout"><aside className="catalog-category-branch"><b>分類を選択</b>{dashboard?.categories.map(c=><button key={c.id} className={selectedProductCategory===c.name?"active":""} onClick={()=>setSelectedProductCategory(c.name)}><i style={{background:c.color}}/><span>{c.name}</span><small>{productsRows.filter(p=>p.category===c.name).length}</small><ChevronLeft className="right"/></button>)}</aside><div className="catalog-table catalog-product-list"><div className="catalog-selected-category"><span>{selectedProductCategory||"分類未選択"}</span><b>{visibleProducts.length}商品</b></div><div className="catalog-labels product-labels"><span>順番</span><span>商品名</span><span>価格</span><span>分類</span><span>キャスト</span><span/></div>{visibleProducts.map((row,i)=><div className="catalog-row product-row" key={row.key}><div className="sort-buttons"><button disabled={i===0} onClick={()=>moveVisibleProduct(row.key,-1)} aria-label={`${row.name||i+1}を上へ`}><ChevronUp/></button><button disabled={i===visibleProducts.length-1} onClick={()=>moveVisibleProduct(row.key,1)} aria-label={`${row.name||i+1}を下へ`}><ChevronDown/></button></div><input aria-label={`${i+1}番目の商品名`} value={row.name} onChange={e=>setProductsRows(x=>x.map(r=>r.key===row.key?{...r,name:e.target.value}:r))} placeholder="商品名"/><div className="price-input"><span>¥</span><input aria-label={`${i+1}番目の価格`} type="number" min="0" step="10" value={row.price} onChange={e=>setProductsRows(x=>x.map(r=>r.key===row.key?{...r,price:Number(e.target.value)}:r))}/></div><select aria-label={`${i+1}番目の分類`} value={row.category} onChange={e=>setProductsRows(x=>x.map(r=>r.key===row.key?{...r,category:e.target.value}:r))}>{dashboard?.categories.map(c=><option value={c.name} key={c.id}>{c.name}</option>)}</select><div className="staff-back-cell"><label><input type="checkbox" aria-label={`${i+1}番目をキャストドリンク対象にする`} checked={row.staffDrink} onChange={e=>setProductsRows(x=>x.map(r=>r.key===row.key?{...r,staffDrink:e.target.checked}:r))}/>対象</label><div className="price-input"><span>戻</span><input aria-label={`${i+1}番目のドリンクバック単価`} type="number" min="0" step="10" value={row.backAmount} onChange={e=>setProductsRows(x=>x.map(r=>r.key===row.key?{...r,backAmount:Number(e.target.value)}:r))}/></div></div><button className="row-delete" onClick={()=>setProductsRows(x=>x.filter(r=>r.key!==row.key))}><Trash2/></button></div>)}{selectedProductCategory?<button className="add-row" onClick={()=>setProductsRows(x=>[...x,{key:`new-${Date.now()}`,name:"",price:0,category:selectedProductCategory,staffDrink:false,backAmount:0}])}><Plus/>{selectedProductCategory}に商品を追加</button>:<div className="catalog-empty">先に分類を登録してください。</div>}</div></div>}
  {error&&<div className="auth-error">{error}</div>}<div className="catalog-actions"><button className="cancel-link" onClick={close}>閉じる</button><button className="login" disabled={saving} onClick={save}>{saving?"保存しています…":saved?<><CheckCircle2/>保存しました</>:"変更を保存"}</button></div></div></div>
}

function DiscountSettingsModal({dashboard,refresh,close}:{dashboard:PosDashboard|null;refresh:()=>Promise<void>;close:()=>void}){
  type Row={key:string;name:string;kind:"amount"|"percent"|"service";value:number};
  const [rows,setRows]=useState<Row[]>(()=>dashboard?.discounts.map(d=>({key:d.id,name:d.name,kind:d.kind,value:d.value}))||[]);
  const [saving,setSaving]=useState(false);const [saved,setSaved]=useState(false);const [error,setError]=useState("");
  const move=(index:number,delta:number)=>setRows(r=>{const next=[...r],to=index+delta;if(to<0||to>=next.length)return r;[next[index],next[to]]=[next[to],next[index]];return next});
  const save=async()=>{setSaving(true);setError("");try{const valid=rows.filter(r=>r.name.trim());await updateDiscountPresets(valid.map(({name,kind,value})=>({name:name.trim(),kind,value})));await refresh();setSaved(true)}catch{setError("保存できませんでした。Administratorログインの有効期限を確認して、もう一度お試しください。")}finally{setSaving(false)}};
  return <div className="modal-backdrop"><div className="catalog-modal discount-settings-modal"><div className="catalog-head"><div><span className="eyebrow">DISCOUNT SETTINGS</span><h2>値引きの設定</h2><p>会計画面で選べる値引きプリセットを編集します。</p></div><button className="modal-x" onClick={close}><X/></button></div>
    <div className="catalog-table">
      <div className="catalog-labels discount-labels"><span>順番</span><span>名前</span><span>種別</span><span>値</span><span/></div>
      {rows.map((row,i)=><div className="catalog-row discount-row" key={row.key}>
        <div className="sort-buttons"><button disabled={i===0} onClick={()=>move(i,-1)} aria-label={`${row.name||i+1}を上へ`}><ChevronUp/></button><button disabled={i===rows.length-1} onClick={()=>move(i,1)} aria-label={`${row.name||i+1}を下へ`}><ChevronDown/></button></div>
        <input aria-label={`${i+1}番目の名前`} value={row.name} onChange={e=>setRows(x=>x.map(r=>r.key===row.key?{...r,name:e.target.value}:r))} placeholder="例：500円引き"/>
        <select aria-label={`${i+1}番目の種別`} value={row.kind} onChange={e=>setRows(x=>x.map(r=>r.key===row.key?{...r,kind:e.target.value as Row["kind"]}:r))}>
          <option value="amount">金額</option><option value="percent">割合(%)</option><option value="service">サービス（手入力）</option>
        </select>
        <div className="price-input"><span>{row.kind==="percent"?"%":"¥"}</span><input aria-label={`${i+1}番目の値`} type="number" min="0" disabled={row.kind==="service"} value={row.kind==="service"?"":row.value} onChange={e=>setRows(x=>x.map(r=>r.key===row.key?{...r,value:Number(e.target.value)}:r))}/></div>
        <button className="row-delete" onClick={()=>setRows(x=>x.filter(r=>r.key!==row.key))}><Trash2/></button>
      </div>)}
      <button className="add-row" onClick={()=>setRows(x=>[...x,{key:`new-${Date.now()}`,name:"",kind:"amount",value:0}])}><Plus/>値引きを追加</button>
    </div>
    {error&&<div className="auth-error">{error}</div>}
    <div className="catalog-actions"><button className="cancel-link" onClick={close}>閉じる</button><button className="login" disabled={saving} onClick={save}>{saving?"保存しています…":saved?<><CheckCircle2/>保存しました</>:"変更を保存"}</button></div>
  </div></div>;
}

function TableSettingsModal({dashboard,refresh,close}:{dashboard:PosDashboard|null;refresh:()=>Promise<void>;close:()=>void}){
  type Row={key:string;name:string;tableNumber:string};
  const [rows,setRows]=useState<Row[]>(()=>dashboard?.tables.map(t=>({key:t.id,name:t.name,tableNumber:t.tableNumber||""}))||[]);
  const [saving,setSaving]=useState(false);const [saved,setSaved]=useState(false);const [error,setError]=useState("");
  const move=(index:number,delta:number)=>setRows(current=>{const next=[...current],to=index+delta;if(to<0||to>=next.length)return current;[next[index],next[to]]=[next[to],next[index]];return next});
  const save=async()=>{setSaving(true);setError("");try{const valid=rows.filter(row=>row.name.trim());if(!valid.length)throw new Error();await updatePosCatalog("tables",valid.map(row=>({name:row.name.trim(),tableNumber:row.tableNumber.trim()})));await refresh();setSaved(true)}catch{setError("卓名を入力してから保存してください。使用中の卓は削除できません。")}finally{setSaving(false)}};
  return <div className="modal-backdrop"><div className="catalog-modal simple-settings-modal"><div className="catalog-head"><div><span className="eyebrow">TABLE SETTINGS</span><h2>卓の設定</h2><p>伝票作成時に選ぶ卓です。矢印でホーム画面の表示順も変更できます。</p></div><button className="modal-x" onClick={close}><X/></button></div><div className="catalog-table"><div className="catalog-labels table-settings-labels"><span>順番</span><span>卓名</span><span>卓番号</span><span/></div>{rows.map((row,i)=><div className="catalog-row table-settings-row" key={row.key}><div className="sort-buttons"><button disabled={i===0} onClick={()=>move(i,-1)} aria-label={`${row.name||i+1}を上へ`}><ChevronUp/></button><button disabled={i===rows.length-1} onClick={()=>move(i,1)} aria-label={`${row.name||i+1}を下へ`}><ChevronDown/></button></div><input value={row.name} aria-label={`${i+1}番目の卓名`} onChange={e=>setRows(x=>x.map(r=>r.key===row.key?{...r,name:e.target.value}:r))} placeholder="例：カウンター 1"/><input value={row.tableNumber} aria-label={`${i+1}番目の卓番号`} onChange={e=>setRows(x=>x.map(r=>r.key===row.key?{...r,tableNumber:e.target.value}:r))} placeholder="例：C-1"/><button className="row-delete" onClick={()=>setRows(x=>x.filter(r=>r.key!==row.key))} aria-label={`${row.name||i+1}を削除`}><Trash2/></button></div>)}<button className="add-row" onClick={()=>setRows(x=>[...x,{key:`new-${Date.now()}`,name:"",tableNumber:""}])}><Plus/>卓を追加</button></div>{error&&<div className="auth-error">{error}</div>}<div className="catalog-actions"><button className="cancel-link" onClick={close}>閉じる</button><button className="login" disabled={saving} onClick={save}>{saving?"保存しています…":saved?<><CheckCircle2/>保存しました</>:"変更を保存"}</button></div></div></div>;
}

function StaffSettingsModal({dashboard,refresh,close}:{dashboard:PosDashboard|null;refresh:()=>Promise<void>;close:()=>void}){
  type Row={key:string;name:string;hourlyWage:number};
  const [rows,setRows]=useState<Row[]>(()=>dashboard?.staff.map(s=>({key:s.id,name:s.name,hourlyWage:s.hourlyWage||0}))||[]);
  const [saving,setSaving]=useState(false);const [saved,setSaved]=useState(false);const [error,setError]=useState("");
  const move=(index:number,delta:number)=>setRows(current=>{const next=[...current],to=index+delta;if(to<0||to>=next.length)return current;[next[index],next[to]]=[next[to],next[index]];return next});
  const save=async()=>{setSaving(true);setError("");try{const valid=rows.filter(row=>row.name.trim());if(!valid.length)throw new Error();await updatePosCatalog("staff",valid.map(row=>({name:row.name.trim(),hourlyWage:Math.max(0,Number(row.hourlyWage)||0)})));await refresh();setSaved(true)}catch{setError("従業員名を入力してから保存してください。")}finally{setSaving(false)}};
  return <div className="modal-backdrop"><div className="catalog-modal simple-settings-modal"><div className="catalog-head"><div><span className="eyebrow">STAFF SETTINGS</span><h2>従業員の設定</h2><p>従業員ドリンクの記録と勤務管理に使用します。時給は給与計算にも使います。</p></div><button className="modal-x" onClick={close}><X/></button></div><div className="catalog-table"><div className="catalog-labels staff-settings-labels"><span>順番</span><span>従業員名</span><span>時給</span><span/></div>{rows.map((row,i)=><div className="catalog-row staff-settings-row" key={row.key}><div className="sort-buttons"><button disabled={i===0} onClick={()=>move(i,-1)} aria-label={`${row.name||i+1}を上へ`}><ChevronUp/></button><button disabled={i===rows.length-1} onClick={()=>move(i,1)} aria-label={`${row.name||i+1}を下へ`}><ChevronDown/></button></div><input value={row.name} aria-label={`${i+1}番目の従業員名`} onChange={e=>setRows(x=>x.map(r=>r.key===row.key?{...r,name:e.target.value}:r))} placeholder="例：佐藤"/><div className="price-input"><span>¥</span><input type="number" min="0" step="10" value={row.hourlyWage||""} aria-label={`${i+1}番目の時給`} onChange={e=>setRows(x=>x.map(r=>r.key===row.key?{...r,hourlyWage:Number(e.target.value)}:r))} placeholder="1,200"/></div><button className="row-delete" onClick={()=>setRows(x=>x.filter(r=>r.key!==row.key))} aria-label={`${row.name||i+1}を削除`}><Trash2/></button></div>)}<button className="add-row" onClick={()=>setRows(x=>[...x,{key:`new-${Date.now()}`,name:"",hourlyWage:0}])}><Plus/>従業員を追加</button></div>{error&&<div className="auth-error">{error}</div>}<div className="catalog-actions"><button className="cancel-link" onClick={close}>閉じる</button><button className="login" disabled={saving} onClick={save}>{saving?"保存しています…":saved?<><CheckCircle2/>保存しました</>:"変更を保存"}</button></div></div></div>;
}

function QrSettingsModal({value,save,close}:{value:string;save:(s:string)=>void;close:()=>void}){
  const [preview,setPreview]=useState(value);const [saved,setSaved]=useState(false);
  const load=(file?:File)=>{if(!file)return;if(file.size>2_000_000){alert("2MB以下の画像を選択してください");return}const reader=new FileReader();reader.onload=()=>setPreview(String(reader.result));reader.readAsDataURL(file)};
  return <div className="modal-backdrop"><div className="qr-settings-modal"><button className="modal-x" onClick={close}><X/></button><div className="shield"><QrCode/></div><span className="eyebrow">PAYMENT QR</span><h2>支払い用QRコード</h2><p>会計で「QR」を選んだときに表示する画像です。</p><div className={`qr-preview ${preview?"has-image":""}`}>{preview?<img src={preview} alt="登録する支払い用QRコード"/>:<><QrCode/><b>QR画像が未登録です</b></>}</div><label className="qr-upload"><ImageUp/>画像を選択<input type="file" accept="image/png,image/jpeg,image/webp" onChange={e=>load(e.target.files?.[0])}/></label>{preview&&<button className="qr-delete" onClick={()=>{setPreview("");setSaved(false)}}><Trash2/>画像を削除</button>}<button className="login" disabled={preview===value&&!saved} onClick={()=>{save(preview);setSaved(true)}}>{saved?<><CheckCircle2/> 保存しました</>:"このQR画像を保存"}</button><small>画像はこの端末のブラウザ内に保存されます。</small></div></div>
}

function GeneralSettingsModal({title,dashboard,refresh,close}:{title:string;dashboard:PosDashboard|null;refresh:()=>Promise<void>;close:()=>void}){
  const defaults:Record<string,string>={"分類":"ビール｜#d8a92d\n焼酎｜#608bb2\nウイスキー｜#987052","商品・価格":"生ビール｜700｜ビール\nハイボール｜800｜ウイスキー","卓の設定":"A卓｜A\nB卓｜B","従業員":"佐藤｜1200\n田中｜1200\n鈴木｜1200","店舗情報":"TIPSY\n東京都\n電話番号","営業日":"06:00","自動ログアウト":"60"};
  const key=`tipsy-setting-${title}`;const [value,setValue]=useState("");const [saved,setSaved]=useState(false);const [saving,setSaving]=useState(false);const [error,setError]=useState("");
  useEffect(()=>{
    const isLiveField=title==="分類"||title==="商品・価格"||title==="卓の設定"||title==="従業員";
    if(isLiveField&&dashboard){
      const live=title==="分類"?dashboard.categories.map(c=>`${c.name}｜${c.color}`).join("\n"):title==="商品・価格"?dashboard.products.map(p=>`${p.name}｜${p.price}｜${p.category}`).join("\n"):title==="卓の設定"?dashboard.tables.map(t=>`${t.name}｜${t.tableNumber||""}`).join("\n"):dashboard.staff.map(s=>`${s.name}｜${s.hourlyWage}`).join("\n");
      setValue(live);
    }else if(!isLiveField){
      setValue(localStorage.getItem(key)||defaults[title]||"");
    }
  },[key,title,dashboard]);
  const multiline=!['営業日','自動ログアウト'].includes(title);
  const save=async()=>{setSaving(true);setError("");try{const rows=value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean);if(title==="分類")await updatePosCatalog("categories",rows.map(x=>{const [name,color]=x.split("｜");return{name,color:color||"#6b7280"}}));else if(title==="商品・価格")await updatePosCatalog("products",rows.map(x=>{const [name,price,category]=x.split("｜");const existing=dashboard?.products.find(p=>p.name===name.trim());return{name,price:Number(price)||0,category:category||"その他",staffDrink:existing?.staffDrink||false,backAmount:existing?.backAmount||0}}));else if(title==="卓の設定")await updatePosCatalog("tables",rows.map(x=>{const [name,tableNumber]=x.split("｜");return{name,tableNumber:tableNumber||""}}));else if(title==="従業員")await updatePosCatalog("staff",rows.map(x=>{const [name,wage]=x.split("｜");return{name,hourlyWage:Number(wage)||0}}));else localStorage.setItem(key,value);await refresh();setSaved(true)}catch{setError("保存できませんでした。オーナーアカウントのログイン状態を確認してください。")}finally{setSaving(false)}};
  return <div className="modal-backdrop"><div className="general-settings-modal"><button className="modal-x" onClick={close}><X/></button><span className="eyebrow">EDIT SETTINGS</span><h2>{title}</h2><p>{title==="分類"?"1行に「分類名｜表示色」で入力してください。":title==="商品・価格"?"1行に「商品名｜価格｜分類」で入力してください。":title==="卓の設定"?"1行に「卓名｜卓番号」で入力してください。":title==="従業員"?"1行に「氏名｜時給（円）」で入力してください。":title==="自動ログアウト"?"Administratorが自動ログアウトするまでの時間（分）です。":title==="営業日"?"営業日の切替時刻を入力してください。":"1項目につき1行で入力してください。"}</p>{multiline?<textarea rows={9} value={value} onChange={e=>{setValue(e.target.value);setSaved(false)}}/>:<input type={title==="営業日"?"time":"number"} min={title==="自動ログアウト"?5:undefined} value={value} onChange={e=>{setValue(e.target.value);setSaved(false)}}/>}{error&&<small className="pin-error">{error}</small>}<button className="login" disabled={saving} onClick={save}>{saving?"保存しています…":saved?<><CheckCircle2/> 保存しました</>:"設定を保存"}</button><button className="cancel-link" onClick={close}>閉じる</button></div></div>
}

function PinSettingsModal({type,close,save}:{type:"staff"|"admin";close:()=>void;save:(pin:string)=>Promise<void>}){
  const [pin,setPin]=useState("");const [confirm,setConfirm]=useState("");const [saved,setSaved]=useState(false);const [saving,setSaving]=useState(false);const [error,setError]=useState("");
  const valid=pin.length===4&&pin===confirm;
  const submit=async()=>{if(!valid||saving)return;setSaving(true);setError("");try{await save(pin);setSaved(true)}catch{setError("Administratorログインを確認して、もう一度お試しください")}finally{setSaving(false)}};
  return <div className="modal-backdrop"><div className="pin-settings-modal"><button className="modal-x" onClick={close}><X/></button><div className="shield">{type==="admin"?<LockKeyhole/>:<KeyRound/>}</div><span className="eyebrow">SECURITY PIN</span><h2>{type==="admin"?"Administrator用PIN":"従業員用PIN"}の設定</h2><p>{type==="admin"?"集計・設定を開くときに使用します":"店舗端末で通常画面を開くときに使用します"}</p>{saved?<div className="pin-saved"><ShieldCheck/><b>PINを変更しました</b><button onClick={close}>閉じる</button></div>:<><label>新しいPIN</label><input inputMode="numeric" type="password" maxLength={4} value={pin} onChange={e=>setPin(e.target.value.replace(/\D/g,""))} placeholder="4桁の数字"/><label>新しいPIN（確認）</label><input inputMode="numeric" type="password" maxLength={4} value={confirm} onChange={e=>setConfirm(e.target.value.replace(/\D/g,""))} placeholder="もう一度入力"/>{confirm&&pin!==confirm&&<small className="pin-error">PINが一致しません</small>}{error&&<small className="pin-error">{error}</small>}<div className="pin-note">従業員用とAdministrator用には異なるPINを設定してください。</div><button className="login" disabled={!valid||saving} onClick={submit}>{saving?"保存しています…":"PINを保存する"}</button></>}</div></div>
}
function PayrollRoundingModal({current,close,refresh}:{current?:{unitMinutes:5|10|15|30;mode:"floor"|"ceil"};close:()=>void;refresh:()=>Promise<void>}){
  const [unit,setUnit]=useState<5|10|15|30>(current?.unitMinutes||15);
  const [mode,setMode]=useState<"floor"|"ceil">(current?.mode||"ceil");
  const [saving,setSaving]=useState(false);const [saved,setSaved]=useState(false);const [error,setError]=useState("");
  const submit=async()=>{setSaving(true);setError("");try{await updatePayrollRounding(unit,mode);await refresh();setSaved(true)}catch{setError("保存できませんでした。Administratorログインの有効期限を確認して、もう一度お試しください。")}finally{setSaving(false)}};
  return <div className="modal-backdrop"><div className="pin-settings-modal"><button className="modal-x" onClick={close}><X/></button><div className="shield"><Timer/></div><span className="eyebrow">PAYROLL ROUNDING</span><h2>給与の端数処理</h2><p>勤務時間（休憩を除く）をこの単位で丸めてから時給を計算します</p>
    <label>丸め単位</label>
    <div className="rounding-choice">{([5,10,15,30] as const).map(m=><button type="button" key={m} className={unit===m?"active":""} onClick={()=>{setUnit(m);setSaved(false)}}>{m}分</button>)}</div>
    <label>丸め方向</label>
    <div className="rounding-choice">
      <button type="button" className={mode==="floor"?"active":""} onClick={()=>{setMode("floor");setSaved(false)}}>切り捨て</button>
      <button type="button" className={mode==="ceil"?"active":""} onClick={()=>{setMode("ceil");setSaved(false)}}>切り上げ</button>
    </div>
    <div className="pin-note">例：{unit}分単位・{mode==="floor"?"切り捨て":"切り上げ"}の場合、3時間{unit===30?"40分":"22分"}の勤務は{mode==="floor"?"切り捨てられ短く":"切り上げられ長く"}計算されます。</div>
    {error&&<small className="pin-error">{error}</small>}
    <button className="login" disabled={saving} onClick={submit}>{saving?"保存しています…":saved?<><CheckCircle2/> 保存しました</>:"設定を保存"}</button>
  </div></div>;
}
function NavButton({icon,label,active,badge,lock,onClick}:{icon:React.ReactNode;label:string;active?:boolean;badge?:string;lock?:boolean;onClick:()=>void}){return <button className={active?"active":""} onClick={onClick}><span>{icon}{badge&&<i>{badge}</i>}</span><b>{label}</b>{lock&&<small>ADMINISTRATOR</small>}</button>}

function OwnerModal({close,enter}:{close:()=>void;enter:(pin:string)=>Promise<boolean>}){const [pin,setPin]=useState("");const [checking,setChecking]=useState(false);const [error,setError]=useState("");const submit=async()=>{if(pin.length!==4||checking)return;setChecking(true);setError("");try{if(!await enter(pin)){setPin("");setError("PINが違います")}}catch{setError("認証に接続できませんでした")}finally{setChecking(false)}};return <div className="modal-backdrop"><div className="owner-modal"><button className="modal-x" onClick={close}><X/></button><div className="shield"><ShieldCheck/></div><span className="eyebrow">ADMINISTRATOR ACCESS</span><h2>Administrator認証</h2><p>4桁のAdministrator PINを入力してください</p><div className="pin-dots">{[0,1,2,3].map(i=><i className={pin.length>i?"filled":""} key={i}/>)}</div><div className="keypad">{[1,2,3,4,5,6,7,8,9,"",0,"⌫"].map((n,i)=><button disabled={n===""||checking} key={i} onClick={()=>n==="⌫"?setPin(pin.slice(0,-1)):setPin((pin+String(n)).slice(0,4))}>{n}</button>)}</div>{error&&<div className="auth-error">{error}</div>}<button className="login" disabled={pin.length<4||checking} onClick={submit}>{checking?"認証しています…":"認証して続ける"}</button></div></div>}

function TimecardView({staff,onShift,toggle,toggleBreak}:{staff:Array<{id:string;name:string}>;onShift:Array<{staffName:string;clockIn:string;onBreak:boolean}>;toggle:(name:string)=>Promise<void>;toggleBreak:(name:string)=>Promise<void>}){
  const [busy,setBusy]=useState("");
  const [error,setError]=useState("");
  const shiftOf=(name:string)=>onShift.find(o=>o.staffName===name);
  const run=async(fn:(name:string)=>Promise<void>,name:string)=>{if(busy)return;setBusy(name);setError("");try{await fn(name)}catch{setError("打刻できませんでした。もう一度お試しください。")}finally{setBusy("")}};
  const onDuty=onShift.filter(o=>!o.onBreak).length,onBreakCount=onShift.filter(o=>o.onBreak).length;
  return <><div className="page-heading"><div><span className="eyebrow">TIME CARD</span><h1>タイムカード</h1><p>お名前をタップして出勤・中抜け・退勤を記録します</p></div></div>
    <div className="stat-row home-stats"><div><span className="dot live"/>出勤中 <b>{onDuty}</b><small>名</small></div><div><Timer size={17}/>中抜け中 <b>{onBreakCount}</b><small>名</small></div></div>
    {error&&<div className="auth-error">{error}</div>}
    {staff.length?<div className="timecard-grid">{staff.map(s=>{
      const shift=shiftOf(s.name);
      const status=shift?(shift.onBreak?"中抜け中":"出勤中"):"未出勤";
      return <div className="timecard-card" key={s.id}>
        <div className="timecard-name"><CircleUserRound/><b>{s.name}</b></div>
        <span className={`timecard-status ${shift?(shift.onBreak?"break":"on"):"off"}`}>{status}{shift?`・${new Date(shift.clockIn).toLocaleTimeString("ja-JP",{hour:"2-digit",minute:"2-digit"})}〜`:""}</span>
        <div className="timecard-actions">
          <button disabled={!!shift||busy===s.name} onClick={()=>run(toggle,s.name)}>出勤</button>
          <button disabled={!shift||busy===s.name} onClick={()=>run(toggleBreak,s.name)}>{shift?.onBreak?"中抜け終了":"中抜け開始"}</button>
          <button disabled={!shift||busy===s.name} onClick={()=>run(toggle,s.name)}>退勤</button>
        </div>
      </div>;
    })}</div>:<div className="empty-home"><ClipboardList/><b>従業員が登録されていません</b><span>設定画面から従業員を登録してください</span></div>}
  </>;
}

function StaffDrinkModal({staff,drinks,close,add}:{staff:Array<{id:string;name:string}>;drinks:Item[];close:()=>void;add:(staff:string,drink:Item)=>void}){
  const [selectedStaff,setSelectedStaff]=useState(staff[0]?.name||"");
  return <div className="modal-backdrop"><div className="staff-drink-modal"><button className="modal-x" onClick={close}><X/></button><span className="eyebrow">STAFF DRINK</span><h2>バック対象商品を追加</h2><p>バックを受け取る出勤中のキャストを選び、商品を追加してください。</p><h3>1. 出勤中のキャスト</h3><div className="staff-choice">{staff.map(s=><button className={selectedStaff===s.name?"active":""} key={s.id} onClick={()=>setSelectedStaff(s.name)}><CircleUserRound/>{s.name}</button>)}</div><h3>2. バック対象商品</h3><div className="drink-choice">{drinks.map(d=><button key={d.id} disabled={!selectedStaff} onClick={()=>add(selectedStaff,d)}><span>{d.name}</span><b>{yen(d.price)}・バック {yen(d.backAmount||0)}</b><Plus/></button>)}</div>{!staff.length&&<div className="auth-error">出勤中のキャストがいません。先にタイムカードで出勤してください。</div>}{!drinks.length&&<div className="auth-error">バック対象の商品が登録されていません。</div>}<button className="cancel-link" onClick={close}>キャンセル</button></div></div>
}

function NewCheckModal({tables,close,start}:{tables:Table[];close:()=>void;start:(table:Table,guest:string,people:number,memo:string)=>void}){
  const [tableId,setTableId]=useState(String(tables[0]?.id||""));const [guest,setGuest]=useState("");const [people,setPeople]=useState(1);const [memo,setMemo]=useState("");const table=tables.find(t=>String(t.id)===tableId);
  return <div className="modal-backdrop"><div className="table-info-modal"><button className="modal-x" onClick={close}><X/></button><span className="eyebrow">NEW CHECK</span><h2>新規伝票を作成</h2><label>卓を選択 <small>空席のみ</small></label><select value={tableId} onChange={e=>setTableId(e.target.value)}>{tables.map(t=><option key={t.id} value={String(t.id)}>{t.name}</option>)}</select><label>お客様名 <small>任意</small></label><input value={guest} onChange={e=>setGuest(e.target.value)} placeholder="例：山田様"/><label>人数</label><div className="people-picker"><button onClick={()=>setPeople(Math.max(1,people-1))}><Minus/></button><strong>{people}<small>名</small></strong><button onClick={()=>setPeople(Math.min(99,people+1))}><Plus/></button></div><label>メモ <small>任意</small></label><textarea rows={3} value={memo} onChange={e=>setMemo(e.target.value)} placeholder="卓やお客様についてのメモ"/>{tables.length===0&&<div className="auth-error">現在、選択できる空席がありません</div>}<button className="login" disabled={!table} onClick={()=>table&&start(table,guest,people,memo)}>この内容で伝票を開始</button><button className="cancel-link" onClick={close}>キャンセル</button></div></div>
}

function TableInfoModal({table,tables,close,start}:{table:Table;tables:Table[];close:()=>void;start:(table:Table,guest:string,people:number,memo:string)=>Promise<void>}){
  const [tableId,setTableId]=useState(String(table.id));const [guest,setGuest]=useState(table.guest||"");const [people,setPeople]=useState(table.people||1);const [memo,setMemo]=useState(table.memo||"");const [saving,setSaving]=useState(false);const [error,setError]=useState("");const target=tables.find(t=>String(t.id)===tableId)||table;
  const submit=async()=>{setSaving(true);setError("");try{await start(target,guest,people,memo)}catch{setError("卓を移動できませんでした。移動先が空席か確認してください。")}finally{setSaving(false)}};
  return <div className="modal-backdrop"><div className="table-info-modal"><button className="modal-x" onClick={close}><X/></button><span className="eyebrow">TABLE INFORMATION</span><h2>卓情報を編集</h2><label>卓 <small>空席へ移動できます</small></label><select value={tableId} onChange={e=>setTableId(e.target.value)}>{tables.map(t=><option key={t.id} value={String(t.id)}>{t.name}{t.id===table.id?"（現在）":""}</option>)}</select><label>お客様名 <small>任意</small></label><input value={guest} onChange={e=>setGuest(e.target.value)} placeholder="例：山田様" autoFocus/><label>人数</label><div className="people-picker"><button onClick={()=>setPeople(Math.max(1,people-1))}><Minus/></button><strong>{people}<small>名</small></strong><button onClick={()=>setPeople(Math.min(99,people+1))}><Plus/></button></div><label>メモ <small>任意</small></label><textarea rows={3} value={memo} onChange={e=>setMemo(e.target.value)} placeholder="卓やお客様についてのメモ"/>{error&&<div className="auth-error">{error}</div>}<button className="login" disabled={saving} onClick={submit}>{saving?"保存しています…":"卓情報を保存"}</button><button className="cancel-link" onClick={close}>キャンセル</button></div></div>
}

function CheckoutLegacy({total,pay,setPay,qr,close,finish}:{total:number;pay:string;setPay:(s:string)=>void;qr:string;close:()=>void;finish:()=>void}){
  const [complete,setComplete]=useState(false);const [received,setReceived]=useState(String(total));
  const change=Math.max(0,(Number(received.replace(/,/g,""))||0)-total);
  if(complete)return <div className="modal-backdrop checkout-wrap"><div className="checkout payment-done"><CheckCircle2/><span className="eyebrow">PAYMENT COMPLETE</span><h2>会計が完了しました</h2><strong>{yen(total)}</strong><p>支払い方法：{pay}</p><button className="complete" onClick={finish}>ホームへ戻る</button><button className="receipt-action" onClick={()=>window.print()}><ReceiptText/>レシートを印刷</button></div></div>;
  return <div className="modal-backdrop checkout-wrap"><div className="checkout"><div className="checkout-head"><button className="icon-btn" onClick={close}><X/></button><div><span className="eyebrow">CHECKOUT</span><h2>お会計</h2></div></div><div className="checkout-total"><small>お支払い合計</small><strong>{yen(total)}</strong><span>消費税（内税） {yen(Math.floor(total/11))}</span></div><h3>支払い方法</h3><div className="payments">{["現金","QR","売掛","その他"].map((p,i)=><button className={pay===p?"active":""} onClick={()=>setPay(p)} key={p}>{[<WalletCards/>,<QrCode/>,<BookOpen/>,<Sparkles/>][i]}<b>{p}</b></button>)}</div>{pay==="現金"&&<div className="cash"><label>お預かり</label><div><span>¥</span><input value={received} inputMode="numeric" onChange={e=>setReceived(e.target.value.replace(/[^0-9,]/g,""))}/></div><p>お釣り <b>{yen(change)}</b></p></div>}{pay==="QR"&&<div className="checkout-qr">{qr?<><img src={qr} alt="支払い用QRコード"/><b>こちらのQRコードを読み取ってください</b><small>決済完了後に下のボタンを押してください</small></>:<><QrCode/><b>支払い用QRコードが未登録です</b><small>設定画面からQR画像を登録してください</small></>}</div>}{pay==="売掛"&&<div className="credit-fields"><input placeholder="売掛先名" required/><input type="date"/><input placeholder="メモ（任意）"/></div>}<button className="complete" disabled={pay==="QR"&&!qr} onClick={()=>setComplete(true)}><ReceiptText/>会計を完了する</button></div></div>}
