globalThis.ResponseType = Object.freeze({ Text: "Text", Json: "Json", JSON: "Json" });
globalThis.Body = Object.freeze({
  json: (payload) => ({ type: "Json", payload }),
  form: (payload) => ({ type: "Form", payload }),
  text: (payload) => ({ type: "Text", payload })
});
function translate(text,from,to,options){
var c=options.config,u=options.utils,fetch=u.tauriFetch,key=c.api_key,base_url=c.base_url,model=c.model;
if(!key||String(key).trim()===""){throw"Sensenova: API Key is required";}
var targetLang=to||"en",base=String(base_url||"https://api.sensenova.cn");
if(base.slice(-3)==="/v1"){base=base.slice(0,-3);}
var url=base+"/v1/chat/completions",prompt="Translate the following text into "+targetLang+". Only output the translated text, no explanations, no quotes, no extra text.\n\n"+text,payload={model:model||"Pythia-Chat",messages:[{role:"user",content:prompt}],stream:false};
return fetch(url,{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+key},body:JSON.stringify(payload)}).then(function(res){
if(!res.ok){throw"Sensenova Http Request Error\nURL: "+url+"\nStatus: "+res.status+"\nBody: "+JSON.stringify(res.data);}
var data=res.data;
var t=data.choices&&data.choices[0]&&data.choices[0].message&&data.choices[0].message.content;
if(t&&String(t).trim()!==""){return String(t).trim();}
throw"Sensenova: no translation received\nResponse: "+JSON.stringify(data);
});
}
