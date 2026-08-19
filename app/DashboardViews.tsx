"use client";
import {useEffect,useState} from "react";
import {BarChart3,ClipboardList,List,ReceiptText,Trash2,UsersRound,X} from "lucide-react";
import {AttendanceDetail,CheckDetail,loadCheckDetail,loadPosAttendanceDetail,loadPosReport,PosDashboard,PosReport,ReportPeriod} from "../lib/store-security";
const yen=(n:number)=>`¥${n.toLocaleString("ja-JP")}`;
const methods:Record<string,string>={cash:"現金",qr:"QR",receivable:"売掛",other:"その他"};
const periodLabel:Record<ReportPeriod,string>={day:"本日",week:"直近7日間",month:"直近30日間"};
const dateLabel=(d:string)=>new Date(`${d}T00:00:00`).toLocaleDateString("ja-JP",{month:"numeric",day:"numeric",weekday:"short"});
const currentMonth=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}`};
const moveMonth=(value:string,amount:number)=>{const [year,month]=value.split("-").map(Number);const d=new Date(year,month-1+amount,1);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}`};

export function HistoryView({dashboard,admin,onDelete}:{dashboard:PosDashboard|null;admin:boolean;onDelete:(id:string)=>Promise<void>}){
  const [deleting,setDeleting]=useState("");
  const [error,setError]=useState("");
  const [openCheck,setOpenCheck]=useState<string|null>(null);
  const remove=async(id:string,number:number)=>{if(!confirm(`伝票 #${String(number).padStart(4,"0")} を削除しますか？\nこの操作は元に戻せません。`))return;setDeleting(id);setError("");try{await onDelete(id)}catch{setError("削除できませんでした。Administratorログインの有効期限を確認して、もう一度お試しください。")}finally{setDeleting("")}};
  const history=dashboard?.history.filter(x=>x.method!=="receivable")||[];
  return <><div className="page-heading"><div><span className="eyebrow">PAYMENT HISTORY</span><h1>会計履歴</h1><p>売掛を除く保存済みの会計を表示します</p></div></div>{error&&<div className="auth-error">{error}</div>}<div className="list-panel">{history.length?history.map(x=><div className="history-row" role="button" tabIndex={0} key={x.id} onClick={()=>setOpenCheck(x.id)} onKeyDown={e=>{if(e.key==="Enter")setOpenCheck(x.id)}}><div className="round-icon"><ReceiptText/></div><div><b>#{String(x.number).padStart(4,"0")}　{x.table||"卓なし"}</b><span>{new Date(x.paidAt).toLocaleString("ja-JP")}・{methods[x.method]||x.method}{x.customer?`・${x.customer}`:""}</span></div><strong>{yen(x.total)}</strong>{admin&&<button className="admin-delete" disabled={deleting===x.id} onClick={e=>{e.stopPropagation();remove(x.id,x.number)}}><Trash2/>{deleting===x.id?"削除中":"削除"}</button>}</div>):<div className="history-row"><div><b>会計履歴はまだありません</b><span>売掛以外の会計完了後にここへ表示されます</span></div></div>}</div>
  {openCheck&&<CheckDetailModal checkId={openCheck} close={()=>setOpenCheck(null)}/>}</>;
}

export function CheckDetailModal({checkId,close}:{checkId:string;close:()=>void}){
  const [detail,setDetail]=useState<CheckDetail|null>(null);
  const [error,setError]=useState("");
  useEffect(()=>{let active=true;loadCheckDetail(checkId).then(d=>{if(active)setDetail(d)}).catch(()=>{if(active)setError("伝票を読み込めませんでした。")});return()=>{active=false}},[checkId]);
  return <div className="modal-backdrop"><div className="table-info-modal check-detail-modal"><button className="modal-x" onClick={close}><X/></button>
    <span className="eyebrow">RECEIPT</span>
    {!detail&&!error&&<p>読み込んでいます…</p>}
    {error&&<div className="auth-error">{error}</div>}
    {detail&&<>
      <h2>#{String(detail.number).padStart(4,"0")}　{detail.table||"卓なし"}</h2>
      <div className="selected-table"><ClipboardList/><div><small>{detail.paidAt?new Date(detail.paidAt).toLocaleString("ja-JP"):"未会計"}・{methods[detail.method||""]||detail.method||"-"}</small><b>{detail.customer||"お名前未入力"}・{detail.guests}名</b></div></div>
      <div className="slip-lines check-detail-lines">{detail.lines.map((l,i)=><div className="line" key={i}><div className="line-main"><b>{l.staff?`${l.staff}／${l.name}`:l.name}</b><small>{yen(l.price)}</small></div><strong>{yen(l.price*l.qty)}</strong><span className="line-qty">×{l.qty}</span></div>)}</div>
      <div className="slip-total"><div><span>小計</span><span>{yen(detail.subtotal)}</span></div>{!!detail.discountAmount&&<div className="checkout-discount-line"><span>値引き（{detail.discountName||"値引き"}）</span><span>-{yen(detail.discountAmount)}</span></div>}<div className="tax">消費税（内税） {yen(detail.tax)}</div><div className="grand"><span>合計</span><strong>{yen(detail.total)}</strong></div>
        {detail.method==="cash"&&detail.receivedAmount!=null&&<div><span>お預かり／お釣り</span><span>{yen(detail.receivedAmount)} ／ {yen(detail.changeAmount||0)}</span></div>}
        {detail.receivable&&<div><span>売掛先</span><span>{detail.receivable.debtorName}{detail.receivable.dueDate?`（期限 ${detail.receivable.dueDate}）`:""}</span></div>}
      </div>
    </>}
  </div></div>;
}

function DailyChart({daily}:{daily:Array<{date:string;sales:number;checks:number}>}){
  const max=Math.max(1,...daily.map(d=>d.sales));
  const barW=26,gap=10,chartH=130;
  const width=Math.max(daily.length*(barW+gap)+gap,280);
  return <div className="daily-chart-wrap"><svg width={width} height={chartH+30} viewBox={`0 0 ${width} ${chartH+30}`} role="img" aria-label="日別売上グラフ">
    <defs><linearGradient id="dailyBarGrad" x1="0" y1="1" x2="0" y2="0"><stop offset="0%" stopColor="#ff2f8f"/><stop offset="100%" stopColor="#00e5ff"/></linearGradient></defs>
    <line x1="0" y1={chartH} x2={width} y2={chartH} stroke="#2d2f4d" strokeWidth="1"/>
    {daily.map((d,i)=>{
      const h=d.sales?Math.max(4,Math.round(d.sales/max*(chartH-18))):0;
      const x=gap+i*(barW+gap);
      const y=chartH-h;
      return <g key={d.date}>
        <title>{`${dateLabel(d.date)} ${yen(d.sales)}（${d.checks}件）`}</title>
        {h>0&&<text x={x+barW/2} y={y-6} textAnchor="middle" fontSize="9" fill="#ffd23f" fontFamily="Orbitron">{d.sales>=1000?`${Math.round(d.sales/1000)}k`:d.sales}</text>}
        <rect x={x} y={y} width={barW} height={h} rx={4} fill="url(#dailyBarGrad)"/>
        <text x={x+barW/2} y={chartH+14} textAnchor="middle" fontSize="9" fill="#8d94c2">{dateLabel(d.date)}</text>
      </g>;
    })}
  </svg></div>;
}

export function ReportsView({dashboard}:{dashboard:PosDashboard|null}){
  const [period,setPeriod]=useState<ReportPeriod>("day");
  const [month,setMonth]=useState(currentMonth);
  const [report,setReport]=useState<PosReport|null>(null);
  const [attendance,setAttendance]=useState<AttendanceDetail[]>([]);
  const [loading,setLoading]=useState(false);
  const [openStaff,setOpenStaff]=useState<string|null>(null);
  const [dailyView,setDailyView]=useState<"list"|"chart">("list");
  useEffect(()=>{
    let active=true;setLoading(true);setOpenStaff(null);
    Promise.all([loadPosReport(period,month),loadPosAttendanceDetail(period,month)]).then(([r,a])=>{if(active){setReport(r);setAttendance(a)}}).catch(console.error).finally(()=>{if(active)setLoading(false)});
    return ()=>{active=false};
  },[period,month]);
  const s=report?.summary||dashboard?.summary;const guests=s?.guests||0,sales=s?.sales||0;
  const rangeText=report?(period==="day"?`営業日 ${report.businessDate}`:`${report.periodStart} 〜 ${report.periodEnd}`):`営業日 ${dashboard?.businessDate||"読み込み中"}`;
  const maxDaily=Math.max(1,...(report?.daily.map(d=>d.sales)||[0]));
  const payTotals=(()=>{const m=new Map<string,{wage:number;back:number}>();(report?.payroll||[]).forEach(p=>m.set(p.name,{wage:p.wageTotal,back:m.get(p.name)?.back||0}));(report?.staffDrinks||[]).forEach(x=>m.set(x.name,{wage:m.get(x.name)?.wage||0,back:x.back}));return [...m.entries()].map(([name,v])=>({name,...v,total:v.wage+v.back})).sort((a,b)=>b.total-a.total)})();
  const selectedStaff=openStaff?{pay:payTotals.find(p=>p.name===openStaff),payroll:report?.payroll.find(p=>p.name===openStaff),drinks:report?.staffDrinks.find(p=>p.name===openStaff)}:null;
  const selectedAttendance=openStaff?attendance.filter(a=>a.staffName===openStaff):[];
  const time=(value:string)=>new Date(value).toLocaleTimeString("ja-JP",{hour:"2-digit",minute:"2-digit"});
  return <><div className="page-heading reports-heading"><div><span className="eyebrow">SALES REPORT</span><h1>{period==="month"?`${Number(month.slice(5))}月分の集計`:`${periodLabel[period]}の集計`}</h1><p>{rangeText}</p></div>
    <div className="report-controls"><div className="period-tabs">
      <button className={period==="day"?"active":""} onClick={()=>setPeriod("day")}>日</button>
      <button className={period==="week"?"active":""} onClick={()=>setPeriod("week")}>週</button>
      <button className={period==="month"?"active":""} onClick={()=>setPeriod("month")}>月</button>
    </div>{period==="month"&&<div className="month-picker"><button aria-label="前月" onClick={()=>setMonth(x=>moveMonth(x,-1))}>‹</button><input type="month" aria-label="集計する月" value={month} onChange={e=>setMonth(e.target.value||currentMonth())}/><button aria-label="翌月" onClick={()=>setMonth(x=>moveMonth(x,1))}>›</button></div>}</div>
  </div><div className={`report-grid ${loading?"report-loading":""}`}><div className="report-main"><small>総売上</small><strong>{yen(sales)}</strong><span>保存済みの会計を集計</span></div>{[["会計件数",`${s?.checks||0}件`],["客数",`${guests}名`],["客単価",yen(guests?Math.floor(sales/guests):0)],["現金売上",yen(s?.cash||0)],["QR売上",yen(s?.qr||0)],["未回収売掛",yen(s?.receivable||0)]].map(x=><div className="metric" key={x[0]}><small>{x[0]}</small><b>{x[1]}</b></div>)}</div>

  {period!=="day"&&<><div className="report-section-head"><h2 className="settings-section-title">日別売上</h2><div className="view-toggle"><button className={dailyView==="list"?"active":""} aria-label="リスト表示" onClick={()=>setDailyView("list")}><List size={15}/></button><button className={dailyView==="chart"?"active":""} aria-label="グラフ表示" onClick={()=>setDailyView("chart")}><BarChart3 size={15}/></button></div></div>
  {dailyView==="chart"?<div className={loading?"report-loading":""}><DailyChart daily={report?.daily||[]}/></div>:
  <div className={`list-panel daily-panel ${loading?"report-loading":""}`}>{report?.daily.length?report.daily.map(d=><div className="daily-row" key={d.date}><span className="daily-date">{dateLabel(d.date)}</span><div className="daily-bar-track"><div className="daily-bar" style={{width:`${d.sales?Math.max(3,Math.round(d.sales/maxDaily*100)):0}%`}}/></div><span className="daily-amount">{yen(d.sales)}</span><span className="daily-checks">{d.checks}件</span></div>):<div className="daily-row"><span>データがありません</span></div>}</div>}</>}

  <h2 className="settings-section-title">スタッフ別支払い合計</h2>
  <div className={`list-panel ${loading?"report-loading":""}`}>{payTotals.length?payTotals.map(p=><button className="history-row staff-payment-row" key={p.name} onClick={()=>setOpenStaff(p.name)}><div className="round-icon"><UsersRound/></div><div><b>{p.name}</b><span>勤務時間・ドリンク内訳を表示</span></div><strong>{yen(p.total)}</strong></button>):<div className="history-row"><div><b>この期間の勤怠・キャストドリンク記録はありません</b><span>出勤／退勤の打刻とキャストドリンクの追加で集計されます</span></div></div>}</div>

  {selectedStaff&&<div className="modal-backdrop"><div className="table-info-modal staff-payment-modal"><button className="modal-x" onClick={()=>setOpenStaff(null)}><X/></button><span className="eyebrow">STAFF PAYMENT DETAIL</span><h2>{openStaff}</h2><div className="staff-payment-summary"><div><span>支払い合計</span><strong>{yen(selectedStaff.pay?.total||0)}</strong></div><div><span>時給分</span><b>{yen(selectedStaff.pay?.wage||0)}</b></div><div><span>ドリンクバック</span><b>{yen(selectedStaff.pay?.back||0)}</b></div></div><h3>勤務</h3><div className="shift-detail-head"><span>日付</span><span>出勤時間</span><span>杯数</span></div><div className="staff-detail-list shift-detail-list">{selectedAttendance.length?selectedAttendance.map((a,i)=><div className="shift-detail-row" key={`${a.clockIn}-${i}`}><span>{period==="day"?dateLabel(a.businessDate):dateLabel(a.businessDate)}</span><b>{time(a.clockIn)} 〜 {a.clockOut?time(a.clockOut):"勤務中"}</b><span className="shift-drink-counts">{a.drinks?.length?a.drinks.map(d=>`${d.name} ${d.count}杯`).join("・"):"—"}</span></div>):<div><span>対象期間の勤務</span><b>なし</b></div>}</div><div className="staff-detail-list staff-detail-totals"><div><span>勤務時間合計</span><b>{selectedStaff.payroll?`${selectedStaff.payroll.hours.toFixed(1)}時間`:"0時間"}</b></div>{period!=="day"&&<div><span>出勤回数</span><b>{selectedStaff.payroll?.shifts||0}回</b></div>}<div><span>時給</span><b>{yen(selectedStaff.payroll?.hourlyWage||0)}</b></div></div><h3>ドリンク</h3><div className="staff-detail-list"><div><span>合計杯数</span><b>{selectedStaff.drinks?.count||0}杯</b></div>{selectedStaff.drinks?.products.length?selectedStaff.drinks.products.map(p=><div key={p.name}><span>{p.name}</span><b>{p.count}杯</b></div>):<div><span>対象期間の記録</span><b>なし</b></div>}</div></div></div>}</>;
}
