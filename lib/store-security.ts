import { createClient } from "./supabase/client";

export const STORE_ID =
  process.env.NEXT_PUBLIC_TIPSY_STORE_ID ??
  "7369b222-060b-4d44-ac95-1256b32c96c4";

export async function verifyStorePin(
  pin: string,
  kind: "staff" | "admin",
) {
  const { data, error } = await createClient().rpc("verify_store_pin", {
    target_store: STORE_ID,
    entered_pin: pin,
    pin_kind: kind,
  });
  if (error) throw error;
  return data === true;
}

export async function updateStorePin(
  pin: string,
  kind: "staff" | "admin",
) {
  const { error } = await createClient().rpc("update_store_pin", {
    target_store: STORE_ID,
    new_pin: pin,
    pin_kind: kind,
    admin_token: localStorage.getItem("tipsy-admin-session"),
  });
  if (error) throw error;
}

export async function openAdminSession(pin:string,minutes:number){
  const {data,error}=await createClient().rpc("open_admin_session",{target_store:STORE_ID,entered_pin:pin,session_minutes:minutes});if(error)throw error;if(typeof data!=="string"||!data)return false;localStorage.setItem("tipsy-admin-session",data);return true;
}
export async function hasValidAdminSession(){const token=localStorage.getItem("tipsy-admin-session");if(!token)return false;const {data}=await createClient().rpc("validate_admin_session",{target_store:STORE_ID,raw_token:token});if(data!==true)localStorage.removeItem("tipsy-admin-session");return data===true}
export function closeAdminSession(){localStorage.removeItem("tipsy-admin-session")}

const POS_TOKEN_KEY = "tipsy-pos-session";

export type SaleLine = {name:string;category:string;price:number;qty:number;staff?:string;backAmount?:number};
export type SaleInput = {tableName:string;customerName:string;guestCount:number;lines:SaleLine[];method:"cash"|"qr"|"receivable"|"other";receivedAmount?:number;debtorName?:string;receivableMemo?:string;dueDate?:string;discountName?:string;discountAmount?:number};

export async function openPosSession(pin: string) {
  const { data, error } = await createClient().rpc("open_pos_session", {
    target_store: STORE_ID,
    entered_pin: pin,
    requested_device_name: navigator.userAgent.slice(0, 80),
  });
  if (error) throw error;
  if (typeof data !== "string" || !data) return false;
  localStorage.setItem(POS_TOKEN_KEY, data);
  return true;
}

export async function hasValidPosSession() {
  const token = localStorage.getItem(POS_TOKEN_KEY);
  if (!token) return false;
  const { data, error } = await createClient().rpc("validate_pos_session", {
    target_store: STORE_ID,
    raw_token: token,
  });
  if (error || data !== true) {
    localStorage.removeItem(POS_TOKEN_KEY);
    return false;
  }
  return true;
}

export async function completePosSale(input:SaleInput){
  const token=localStorage.getItem(POS_TOKEN_KEY);
  if(!token) throw new Error("店舗端末の再認証が必要です");
  const {data,error}=await createClient().rpc("complete_saved_pos_sale",{
    target_store:STORE_ID,raw_token:token,table_name:input.tableName,
    customer_name:input.customerName,guest_count:input.guestCount,lines:input.lines,
    payment_method:input.method,received_amount:input.receivedAmount??null,
    debtor_name:input.debtorName??null,receivable_memo:input.receivableMemo??"",
    due_date:input.dueDate||null,
    discount_name:input.discountName||null,discount_amount:input.discountAmount??0,
  });
  if(error) throw error;
  return data as {check_id:string;check_number:number;total:number};
}

export async function saveOpenCheck(input:{tableName:string;customerName:string;guestCount:number;lines:SaleLine[];memo?:string}){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=await createClient().rpc("save_pos_open_check",{target_store:STORE_ID,raw_token:token,table_name:input.tableName,customer_name:input.customerName,guest_count:input.guestCount,lines:input.lines,check_memo:input.memo??""});
  if(error)throw error;return data as {checkId:string;total:number};
}

export async function moveOpenCheck(checkId:string,tableName:string){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {error}=await createClient().rpc("move_pos_open_check",{target_store:STORE_ID,raw_token:token,check_id:checkId,new_table_name:tableName});
  if(error)throw error;
}

export type PosDashboard={businessDate:string;tables:Array<{id:string;name:string;tableNumber:string;checkId?:string;guest?:string;people?:number;total?:number;memo?:string;lines?:SaleLine[]}>;categories:Array<{id:string;name:string;color:string}>;products:Array<{id:string;name:string;category:string;price:number;color:string;staffDrink:boolean;backAmount:number}>;staff:Array<{id:string;name:string;hourlyWage:number}>;onShift:Array<{staffName:string;clockIn:string;onBreak:boolean}>;payrollRounding:{unitMinutes:5|10|15|30;mode:"floor"|"ceil"};discounts:Array<{id:string;name:string;kind:"amount"|"percent"|"service";value:number}>;history:Array<{id:string;number:number;table:string;customer:string;guests:number;total:number;paidAt:string;method:string}>;summary:{sales:number;checks:number;guests:number;cash:number;qr:number;receivable:number;other:number}};
export async function loadPosDashboard(){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=await createClient().rpc("get_pos_dashboard",{target_store:STORE_ID,raw_token:token});
  if(error)throw error;return data as PosDashboard;
}

export type ReportPeriod = "day"|"week"|"month";
export type PosReport = {period:ReportPeriod;businessDate:string;periodStart:string;periodEnd:string;summary:{sales:number;checks:number;guests:number;cash:number;qr:number;receivable:number;other:number};staffDrinks:Array<{name:string;count:number;back:number;products:Array<{name:string;count:number}>}>;daily:Array<{date:string;sales:number;checks:number}>;payroll:Array<{name:string;hours:number;hourlyWage:number;wageTotal:number;shifts:number}>};
export async function loadPosReport(period:ReportPeriod,month?:string){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=period==="month"&&month
    ?await createClient().rpc("get_pos_report_month",{target_store:STORE_ID,raw_token:token,target_month:`${month}-01`})
    :await createClient().rpc("get_pos_report",{target_store:STORE_ID,raw_token:token,period});
  if(error)throw error;return data as PosReport;
}

export type PosReceivable={id:string;checkId:string;number:number;table:string;debtorName:string;amount:number;memo:string;dueDate?:string;createdAt:string};
export async function loadPosReceivables(){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=await createClient().rpc("get_pos_receivables",{target_store:STORE_ID,raw_token:token});
  if(error)throw error;return data as PosReceivable[];
}
export async function settlePosReceivable(receivableId:string,method:"cash"|"qr"|"other"){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=await createClient().rpc("settle_pos_receivable",{target_store:STORE_ID,raw_token:token,target_receivable:receivableId,paid_method:method});
  if(error)throw error;return data===true;
}
export type AttendanceDetail={staffName:string;businessDate:string;clockIn:string;clockOut?:string;drinks:Array<{name:string;count:number}>};
export async function loadPosAttendanceDetail(period:ReportPeriod,month?:string){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=period==="month"&&month
    ?await createClient().rpc("get_pos_attendance_detail_month",{target_store:STORE_ID,raw_token:token,target_month:`${month}-01`})
    :await createClient().rpc("get_pos_attendance_detail",{target_store:STORE_ID,raw_token:token,period});
  if(error)throw error;return data as AttendanceDetail[];
}

export type CheckDetail = {id:string;number:number;table:string;customer:string;guests:number;subtotal:number;discountName?:string;discountAmount?:number;tax:number;total:number;status:string;openedAt:string;paidAt?:string;method?:string;receivedAmount?:number;changeAmount?:number;receivable?:{debtorName:string;dueDate?:string;memo:string;status:string};lines:Array<{name:string;category:string;staff?:string;price:number;qty:number;backAmount:number}>};
export async function loadCheckDetail(checkId:string){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=await createClient().rpc("get_pos_check_detail",{target_store:STORE_ID,raw_token:token,target_check:checkId});
  if(error)throw error;return data as CheckDetail;
}

export async function toggleAttendance(staffName:string){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=await createClient().rpc("toggle_attendance",{target_store:STORE_ID,raw_token:token,staff_name:staffName});
  if(error)throw error;return data as {action:"in"|"out";staffName:string;at:string};
}

export async function toggleBreak(staffName:string){
  const token=localStorage.getItem(POS_TOKEN_KEY);if(!token)throw new Error("店舗端末の再認証が必要です");
  const {data,error}=await createClient().rpc("toggle_break",{target_store:STORE_ID,raw_token:token,staff_name:staffName});
  if(error)throw error;return data as {action:"break_start"|"break_end";staffName:string;at:string};
}

export async function updatePayrollRounding(unitMinutes:5|10|15|30,mode:"floor"|"ceil"){
  const {error}=await createClient().rpc("update_payroll_rounding",{target_store:STORE_ID,unit_minutes:unitMinutes,round_mode:mode,admin_token:localStorage.getItem("tipsy-admin-session")});
  if(error)throw error;
}

export async function updateDiscountPresets(items:Array<{name:string;kind:"amount"|"percent"|"service";value:number}>){
  const {error}=await createClient().rpc("update_discount_presets",{target_store:STORE_ID,items,admin_token:localStorage.getItem("tipsy-admin-session")});
  if(error)throw error;
}

export async function updatePosCatalog(kind:"categories"|"products"|"tables"|"staff",items:Array<Record<string,string|number|boolean>>){
  const {error}=await createClient().rpc("update_pos_catalog",{target_store:STORE_ID,catalog_kind:kind,items,admin_token:localStorage.getItem("tipsy-admin-session")});
  if(error)throw error;
}

export async function deletePosCheck(checkId:string){
  const {data,error}=await createClient().rpc("delete_pos_check",{target_store:STORE_ID,target_check:checkId,admin_token:localStorage.getItem("tipsy-admin-session")});
  if(error)throw error;return data===true;
}
