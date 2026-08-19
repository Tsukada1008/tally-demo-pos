"use client";

import {useState} from "react";
import {BookOpen,CheckCircle2,Delete,QrCode,ReceiptText,Sparkles,WalletCards,X} from "lucide-react";

const yen=(n:number)=>`¥${n.toLocaleString("ja-JP")}`;

type Discount={id:string;name:string;kind:"amount"|"percent"|"service";value:number};

export default function Checkout({total,pay,setPay,qr,discounts,close,save,finish}:{total:number;pay:string;setPay:(s:string)=>void;qr:string;discounts:Discount[];close:()=>void;save:(details:{received:number;debtorName:string;memo:string;dueDate:string;discountName:string;discountAmount:number})=>Promise<unknown>;finish:()=>void}){
  const subtotal=total;
  const [complete,setComplete]=useState(false);
  const [saving,setSaving]=useState(false);
  const [error,setError]=useState("");
  const [received,setReceived]=useState("");
  const [debtorName,setDebtorName]=useState("");
  const [memo,setMemo]=useState("");
  const [dueDate,setDueDate]=useState("");
  const [discountId,setDiscountId]=useState("");
  const [serviceAmount,setServiceAmount]=useState("");
  const selectedDiscount=discounts.find(d=>d.id===discountId);
  const discountAmount=!selectedDiscount?0
    :selectedDiscount.kind==="amount"?Math.min(subtotal,Math.round(selectedDiscount.value))
    :selectedDiscount.kind==="percent"?Math.min(subtotal,Math.floor(subtotal*selectedDiscount.value/100))
    :Math.min(subtotal,Number(serviceAmount)||0);
  const grandTotal=Math.max(0,subtotal-discountAmount);
  const receivedNumber=Number(received)||0;
  const change=Math.max(0,receivedNumber-grandTotal);
  const valid=pay!=="現金"||receivedNumber>=grandTotal;
  const receivableValid=pay!=="売掛"||debtorName.trim().length>0;
  const typeAmount=(value:string)=>setReceived(current=>current.length>=9?current:current+value);
  const submit=async()=>{
    if(saving||!valid||!receivableValid||(pay==="QR"&&!qr))return;
    setSaving(true);setError("");
    try{await save({received:receivedNumber,debtorName,memo,dueDate,discountName:selectedDiscount?.name||"",discountAmount});setComplete(true)}
    catch(e){console.error(e);setError("会計を保存できませんでした。通信を確認してもう一度お試しください。")}finally{setSaving(false)}
  };

  if(complete)return <div className="modal-backdrop checkout-wrap"><div className="checkout payment-done"><CheckCircle2/><span className="eyebrow">PAYMENT COMPLETE</span><h2>会計が完了しました</h2><strong>{yen(grandTotal)}</strong><p>支払い方法：{pay}</p><button className="complete" onClick={finish}>ホームへ戻る</button><button className="receipt-action" onClick={()=>window.print()}><ReceiptText/>レシートを印刷</button></div></div>;

  return <div className="modal-backdrop checkout-wrap"><div className="checkout">
    <div className="checkout-head"><button className="icon-btn" onClick={close} disabled={saving}><X/></button><div><span className="eyebrow">CHECKOUT</span><h2>お会計</h2></div></div>
    <div className="checkout-total">
      {discountAmount>0?<><small>小計 {yen(subtotal)}</small><span className="checkout-discount-line">値引き（{selectedDiscount?.name}） -{yen(discountAmount)}</span></>:<small>お支払い合計</small>}
      <strong>{yen(grandTotal)}</strong>
      <span>消費税（内税） {yen(Math.floor(grandTotal/11))}</span>
    </div>
    {!!discounts.length&&<>
      <h3>値引き</h3>
      <div className="discount-choice">
        <button type="button" className={!discountId?"active":""} disabled={saving} onClick={()=>setDiscountId("")}><b>なし</b></button>
        {discounts.map(d=><button type="button" key={d.id} className={discountId===d.id?"active":""} disabled={saving} onClick={()=>setDiscountId(d.id)}><b>{d.name}</b><span>{d.kind==="amount"?`-${yen(d.value)}`:d.kind==="percent"?`-${d.value}%`:"金額入力"}</span></button>)}
      </div>
      {selectedDiscount?.kind==="service"&&<div className="price-input service-amount-input"><span>¥</span><input inputMode="numeric" type="number" min="0" value={serviceAmount} onChange={e=>setServiceAmount(e.target.value.replace(/[^0-9]/g,""))} placeholder="値引き額"/></div>}
    </>}
    <h3>支払い方法</h3><div className="payments">{["現金","QR","売掛","その他"].map((method,index)=><button className={pay===method?"active":""} onClick={()=>setPay(method)} key={method} disabled={saving}>{[<WalletCards key="cash"/>,<QrCode key="qr"/>,<BookOpen key="credit"/>,<Sparkles key="other"/>][index]}<b>{method}</b></button>)}</div>
    {pay==="現金"&&<div className="cash cash-pin"><label>お預かり</label><div className="cash-display"><span>¥</span><strong>{received?Number(received).toLocaleString("ja-JP"):"0"}</strong></div><button className="exact-amount" onClick={()=>setReceived(String(grandTotal))}>ちょうど {yen(grandTotal)}</button><div className="cash-keypad">{["1","2","3","4","5","6","7","8","9","00","0","⌫"].map(key=><button type="button" key={key} onClick={()=>key==="⌫"?setReceived(value=>value.slice(0,-1)):typeAmount(key)}>{key==="⌫"?<Delete/>:key}</button>)}</div><p>お釣り <b>{yen(change)}</b></p>{received!==""&&!valid&&<small className="pin-error">預かり金額が不足しています</small>}</div>}
    {pay==="QR"&&<div className="checkout-qr">{qr?<><img src={qr} alt="支払い用QRコード"/><b>こちらのQRコードを読み取ってください</b><small>決済完了後に下のボタンを押してください</small></>:<><QrCode/><b>支払い用QRコードが未登録です</b><small>設定画面からQR画像を登録してください</small></>}</div>}
    {pay==="売掛"&&<div className="credit-fields"><input placeholder="売掛先名" value={debtorName} onChange={e=>setDebtorName(e.target.value)} required/><input type="date" value={dueDate} onChange={e=>setDueDate(e.target.value)}/><input placeholder="メモ（任意）" value={memo} onChange={e=>setMemo(e.target.value)}/></div>}
    {error&&<div className="auth-error">{error}</div>}<button className="complete" disabled={saving||!valid||!receivableValid||(pay==="QR"&&!qr)} onClick={submit}><ReceiptText/>{saving?"会計を保存しています…":"会計を完了する"}</button>
  </div></div>;
}
