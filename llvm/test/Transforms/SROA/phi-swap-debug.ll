; RUN: opt -passes=sroa -verify-each -S %s | FileCheck %s

; Leave physical-slot debug locations on the existing SROA paths.
define i64 @debug_slot(ptr %output, i64 %x, i64 %y, i32 %n) !dbg !4 {
; CHECK-LABEL: @debug_slot(
; CHECK: phi ptr
; CHECK: phi ptr
entry:
  %a = alloca i64, align 8
  #dbg_declare(ptr %a, !5, !DIExpression(), !6)
  %b = alloca i64, align 8
  store i64 %x, ptr %a, align 8
  store i64 %y, ptr %b, align 8
  br label %loop
loop:
  %p = phi ptr [ %a, %entry ], [ %q, %loop ]
  %q = phi ptr [ %b, %entry ], [ %p, %loop ]
  %i = phi i32 [ 0, %entry ], [ %next, %loop ]
  %pv = load i64, ptr %p, align 8
  %qv = load i64, ptr %q, align 8
  %newp = add i64 %pv, %qv
  store i64 %newp, ptr %p, align 8
  store i64 %pv, ptr %q, align 8
  store i64 %newp, ptr %output, align 1
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, %n
  br i1 %done, label %exit, label %loop
exit:
  ret i64 %newp
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!7}
!0 = distinct !DICompileUnit(language: DW_LANG_C, file: !1, producer: "test", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "test.c", directory: "/")
!2 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!3 = !DISubroutineType(types: !{})
!4 = distinct !DISubprogram(name: "debug_slot", scope: !1, file: !1, line: 1, type: !3, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!5 = !DILocalVariable(name: "slot", scope: !4, file: !1, line: 1, type: !2)
!6 = !DILocation(line: 1, column: 1, scope: !4)
!7 = !{i32 2, !"Debug Info Version", i32 3}
