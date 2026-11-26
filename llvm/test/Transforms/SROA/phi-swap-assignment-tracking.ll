; RUN: opt -passes=sroa -S %s | FileCheck %s

; Leave assignment tracking to the existing SROA paths.
define i64 @assignment_tracking(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @assignment_tracking(
; CHECK: phi ptr
; CHECK: phi ptr
entry:
  %a = alloca i64, align 8
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

!llvm.module.flags = !{!0}
!0 = !{i32 7, !"debug-info-assignment-tracking", i1 true}
