import type {MetadataRoute} from "next";

export default function manifest():MetadataRoute.Manifest{
  const demo=process.env.NEXT_PUBLIC_APP_ENV==="demo";
  const name=demo?"Tally CHECK":"TIPSY CHECK";
  return {
    id:"/",
    name,
    short_name:demo?"Tally":"TIPSY",
    description:"バー専用 会計・伝票管理アプリ",
    start_url:"/",
    scope:"/",
    display:"standalone",
    orientation:"any",
    background_color:"#151719",
    theme_color:"#151719",
    lang:"ja",
    categories:["business","productivity"],
    icons:[
      {src:"/icons/icon-192.png",sizes:"192x192",type:"image/png",purpose:"any"},
      {src:"/icons/icon-512.png",sizes:"512x512",type:"image/png",purpose:"any"},
      {src:"/icons/icon-maskable-512.png",sizes:"512x512",type:"image/png",purpose:"maskable"}
    ]
  };
}
