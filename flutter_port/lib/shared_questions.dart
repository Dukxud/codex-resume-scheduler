part of 'main.dart';

/// Questions belong to the single shared App Server, never another Codex process.
class SharedQuestionsPanel extends StatelessWidget {
  const SharedQuestionsPanel({super.key, required this.state, required this.onAnswer});
  final Map<String, dynamic> state;
  final Future<void> Function(String id, Map<String, dynamic> answer) onAnswer;

  @override
  Widget build(BuildContext context) {
    final questions=recordList(field(state,'questions'));
    final chunks=field(state,'messages');
    final transcript=chunks is List ? chunks.whereType<String>().join('') : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start,children:[
      Text(questions.isNotEmpty ? 'CODEX NEEDS YOUR INPUT' : 'SHARED CODEX SESSION',
        style:const TextStyle(color:DeckColor.aqua,fontWeight:FontWeight.w800,fontSize:11)),
      const SizedBox(height:8),
      if(questions.isEmpty)
        Text('Status: '+stringField(state,'status'),
          style:const TextStyle(color:DeckColor.text,fontSize:12)),
      for(final q in questions)_question(context,q),
      if(transcript.isNotEmpty)...[
        const SizedBox(height:12),
        const Text('ASSISTANT OUTPUT',style:TextStyle(color:DeckColor.muted,fontSize:10)),
        SelectableText(transcript,style:const TextStyle(color:DeckColor.text,fontSize:12)),
      ],
    ]);
  }

  Widget _question(BuildContext context,Map<String,dynamic> question){
    final id=stringField(question,'id');
    final method=stringField(question,'method');
    final raw=field(question,'params');
    final params=raw is Map ? Map<String,dynamic>.from(raw) : <String,dynamic>{};
    final approval=method=='item/commandExecution/requestApproval' ||
      method=='item/fileChange/requestApproval';
    final userInput=method=='item/tool/requestUserInput';
    final permissions=method=='item/permissions/requestApproval';
    final elicitation=method=='mcpServer/elicitation/request';
    return Container(
      key:Key('shared-question-$id'),
      margin:const EdgeInsets.only(top:9),
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(
        color:const Color(0xff202942),
        border:Border.all(color:DeckColor.aqua.withValues(alpha:.34)),
        borderRadius:BorderRadius.circular(12)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(approval?'APPROVAL REQUEST':userInput?'QUESTION FROM CODEX':
          permissions?'PERMISSION REQUEST':elicitation?'CONNECTED APP REQUEST':'INPUT REQUIRED',
          style:const TextStyle(color:DeckColor.aqua,fontSize:11,fontWeight:FontWeight.w800)),
        const SizedBox(height:7),
        SelectableText(const JsonEncoder.withIndent('  ').convert(params),
          style:const TextStyle(color:DeckColor.text,fontSize:11)),
        const SizedBox(height:9),
        Wrap(spacing:8,runSpacing:8,children:[
          if(approval)...[
            FilledButton(key:Key('shared-approve-$id'),
              onPressed:()=>onAnswer(id,{'decision':'accept'}),
              child:const Text('Approve once')),
            OutlinedButton(key:Key('shared-decline-$id'),
              onPressed:()=>onAnswer(id,{'decision':'decline'}),
              child:const Text('Decline')),
          ],
          if(userInput)
            FilledButton(key:Key('shared-respond-$id'),
              onPressed:()=>_inputDialog(context,id,params),
              child:const Text('Answer question')),
          if(permissions)...[
            FilledButton(key:Key('shared-grant-$id'),
              onPressed:() async{
                final confirmed=await showDialog<bool>(context:context,
                  builder:(dialog)=>AlertDialog(
                    title:const Text('Grant requested permissions?'),
                    content:const Text('Review the requested permissions above.'),
                    actions:[
                      TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Cancel')),
                      FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('Grant')),
                    ]));
                final p=field(params,'permissions');
                if(confirmed==true && p is Map)await onAnswer(id,{'permissions':p});
              },child:const Text('Grant requested')),
            OutlinedButton(key:Key('shared-deny-$id'),
              onPressed:()=>onAnswer(id,{'permissions':<String,dynamic>{}}),
              child:const Text('Deny')),
          ],
          if(elicitation)
            OutlinedButton(key:Key('shared-cancel-$id'),
              onPressed:()=>onAnswer(id,{'action':'decline','content':null}),
              child:const Text('Decline')),
        ]),
      ]),
    );
  }

  Future<void> _inputDialog(BuildContext context,String id,Map<String,dynamic> params) async{
    final questions=recordList(field(params,'questions'));
    if(questions.isEmpty)return;
    final controllers=<String,TextEditingController>{
      for(final q in questions)stringField(q,'id'):TextEditingController(),
    };
    try{
      final submitted=await showDialog<bool>(context:context,
        builder:(dialog)=>AlertDialog(
          title:const Text('Answer Codex'),
          content:SizedBox(width:430,child:SingleChildScrollView(
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              for(final q in questions)
                Padding(padding:const EdgeInsets.symmetric(vertical:6),
                  child:TextField(
                    key:Key('shared-input-'+stringField(q,'id')),
                    controller:controllers[stringField(q,'id')],
                    maxLines:3,
                    decoration:InputDecoration(
                      labelText:stringField(q,'header').isEmpty
                        ? stringField(q,'id') : stringField(q,'header'),
                      helperText:stringField(q,'question').isEmpty
                        ? null : stringField(q,'question'),
                      helperMaxLines:4))),
            ]),
          )),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Cancel')),
            FilledButton(key:const Key('submit-shared-answer'),
              onPressed:()=>Navigator.pop(dialog,true),child:const Text('Send answer')),
          ]));
      if(submitted==true){
        final answers=<String,dynamic>{};
        for(final entry in controllers.entries){
          answers[entry.key]={'answers':[entry.value.text]};
        }
        await onAnswer(id,{'answers':answers});
      }
    }finally{
      for(final c in controllers.values){c.dispose();}
    }
  }
}
