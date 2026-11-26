; RUN: opt -passes='sroa<preserve-cfg>,verify<domtree>' -verify-each -S %s | FileCheck %s
; RUN: opt -passes='sroa<modify-cfg>,verify<domtree>' -verify-each -S %s | FileCheck %s

target datalayout = "e-p:64:64-i64:64-i128:128-n8:16:32:64-S128"

declare void @escape(ptr)
declare void @sub_block(ptr captures(none) writeonly, <2 x i64>) memory(argmem: write)
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)
declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1 immarg)
declare void @llvm.lifetime.start.p0(ptr captures(none))
declare void @llvm.lifetime.end.p0(ptr captures(none))

; Keep the first input read before memmove, and the tail read after it: the
; caller may overlap input and output. The helper still writes to a third slot.
define void @swap_vectors(ptr %input, ptr %output, i32 %n) {
; CHECK-LABEL: @swap_vectors(
; CHECK: [[TMP:%.*]] = alloca <2 x i64>, align 16
; CHECK-NOT: alloca
; CHECK: [[FIRST:%.*]] = load <16 x i8>, ptr %input, align 1
; CHECK-NEXT: call void @llvm.memmove.p0.p0.i64(ptr align 1 %output, ptr align 1 %input, i64 16, i1 false)
; CHECK-NEXT: [[TAILPTR:%.*]] = getelementptr i8, ptr %input, i64 16
; CHECK-NEXT: [[TAIL:%.*]] = load i64, ptr [[TAILPTR]], align 1
; CHECK: loop:
; CHECK-NEXT: [[P:%.*]] = phi <16 x i8> [ [[FIRST]], %preheader ], [ [[NEXTQ:%.*]], %loop ]
; CHECK-NEXT: [[Q:%.*]] = phi <16 x i8> [ {{%.*}}, %preheader ], [ %newp, %loop ]
; CHECK-NEXT: %i = phi i32
; CHECK-NEXT: [[QV:%.*]] = bitcast <16 x i8> [[Q]] to <2 x i64>
; CHECK-NEXT: call void @sub_block(ptr [[TMP]], <2 x i64> [[QV]])
; CHECK-NEXT: [[AGAIN:%.*]] = bitcast <16 x i8> [[Q]] to <2 x i64>
; CHECK-NEXT: [[H:%.*]] = load <2 x i64>, ptr [[TMP]], align 16
; CHECK-NEXT: %newq = xor <2 x i64> [[AGAIN]], [[H]]
; CHECK-NEXT: [[NEXTQ]] = bitcast <2 x i64> %newq to <16 x i8>
; CHECK-NEXT: %newp = xor <16 x i8> [[P]], splat (i8 1)
; CHECK-NEXT: store <16 x i8> [[NEXTQ]], ptr %output, align 1
; CHECK-NEXT: %second = getelementptr i8, ptr %output, i64 16
; CHECK-NEXT: store <16 x i8> %newp, ptr %second, align 1
; CHECK-NOT: phi ptr
; CHECK-NOT: load
; CHECK: ret void
entry:
  %a = alloca [1 x <2 x i64>], align 16
  %b = alloca [1 x <2 x i64>], align 16
  %tmp = alloca <2 x i64>, align 16
  br label %preheader
preheader:
  call void @llvm.lifetime.start.p0(ptr %a)
  call void @llvm.lifetime.start.p0(ptr %b)
  call void @llvm.memcpy.p0.p0.i64(ptr align 16 %a, ptr align 1 %input, i64 16, i1 false)
  call void @llvm.memmove.p0.p0.i64(ptr align 1 %output, ptr align 1 %input, i64 16, i1 false)
  %tailptr = getelementptr i8, ptr %input, i64 16
  %tail = load i64, ptr %tailptr, align 1
  store i64 %tail, ptr %b, align 16
  %high = getelementptr i8, ptr %b, i64 8
  store i64 0, ptr %high, align 8
  br label %loop
loop:
  %p = phi ptr [ %a, %preheader ], [ %q, %loop ]
  %q = phi ptr [ %b, %preheader ], [ %p, %loop ]
  %i = phi i32 [ 0, %preheader ], [ %next, %loop ]
  %qv = load <2 x i64>, ptr %q, align 16
  call void @sub_block(ptr %tmp, <2 x i64> %qv)
  %again = load <2 x i64>, ptr %q, align 16
  %h = load <2 x i64>, ptr %tmp, align 16
  %newq = xor <2 x i64> %again, %h
  store <2 x i64> %newq, ptr %q, align 16
  %pv = load <16 x i8>, ptr %p, align 16
  %newp = xor <16 x i8> %pv, splat (i8 1)
  store <16 x i8> %newp, ptr %p, align 16
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %output, ptr align 16 %q, i64 16, i1 false)
  %second = getelementptr i8, ptr %output, i64 16
  call void @llvm.memmove.p0.p0.i64(ptr align 1 %second, ptr align 16 %p, i64 16, i1 false)
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, %n
  br i1 %done, label %exit, label %loop
exit:
  call void @llvm.lifetime.end.p0(ptr %a)
  call void @llvm.lifetime.end.p0(ptr %b)
  ret void
}

define i64 @swap_i64(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @swap_i64(
; CHECK-NEXT: entry:
; CHECK-NEXT: br label %loop
; CHECK: loop:
; CHECK-NEXT: [[P:%.*]] = phi i64 [ %x, %entry ], [ [[P]], %loop ]
; CHECK-NEXT: [[Q:%.*]] = phi i64 [ %y, %entry ], [ %newp, %loop ]
; CHECK-NEXT: %i = phi i32
; CHECK-NEXT: %newp = add i64 [[P]], [[Q]]
; CHECK-NEXT: store i64 %newp, ptr %output, align 1
; CHECK-NOT: load
; CHECK-NOT: alloca
; CHECK: ret i64 %newp
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

define i64 @captured_alloca(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @captured_alloca(
; CHECK: phi ptr
; CHECK: phi ptr
entry:
  %a = alloca i64, align 8
  %b = alloca i64, align 8
  store i64 %x, ptr %a, align 8
  store i64 %y, ptr %b, align 8
  call void @escape(ptr %a)
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

define i64 @captured_phi(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @captured_phi(
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
  call void @escape(ptr %q)
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

define i64 @compare_addresses(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @compare_addresses(
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
  %cmp = icmp eq ptr %p, %q
  store i1 %cmp, ptr %output, align 1
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

define i64 @observed_after_loop(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @observed_after_loop(
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
  %after = load i64, ptr %a, align 8
  store i64 %after, ptr %output, align 1
  ret i64 %newp
}

define i64 @direct_loop_access(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @direct_loop_access(
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
  store i64 7, ptr %a, align 8
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

define i64 @lifetime_end_in_loop(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @lifetime_end_in_loop(
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
  call void @llvm.lifetime.end.p0(ptr %a)
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

define i64 @derived_loop_address(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @derived_loop_address(
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
  %off = getelementptr i8, ptr %p, i64 1
  %part = load i8, ptr %off, align 1
  store i8 %part, ptr %output, align 1
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

define i64 @partial_copy(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @partial_copy(
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
  call void @llvm.memcpy.p0.p0.i64(ptr %output, ptr %q, i64 4, i1 false)
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

define i64 @copy_into_slot(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @copy_into_slot(
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
  call void @llvm.memcpy.p0.p0.i64(ptr %q, ptr %output, i64 8, i1 false)
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

define i64 @volatile_load(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @volatile_load(
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
  %pv = load volatile i64, ptr %p, align 8
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

define i64 @volatile_store(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @volatile_store(
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
  store volatile i64 %newp, ptr %p, align 8
  store i64 %pv, ptr %q, align 8
  store i64 %newp, ptr %output, align 1
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, %n
  br i1 %done, label %exit, label %loop
exit:
  ret i64 %newp
}

define i64 @atomic_load(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @atomic_load(
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
  %pv = load atomic i64, ptr %p monotonic, align 8
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

define i64 @atomic_store(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @atomic_store(
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
  store atomic i64 %newp, ptr %p monotonic, align 8
  store i64 %pv, ptr %q, align 8
  store i64 %newp, ptr %output, align 1
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, %n
  br i1 %done, label %exit, label %loop
exit:
  ret i64 %newp
}

define i64 @partial_load(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @partial_load(
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
  %part = load i32, ptr %p, align 4
  %pv = zext i32 %part to i64
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

define i64 @same_initial_slot(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @same_initial_slot(
; CHECK: phi ptr
entry:
  %a = alloca i64, align 8
  %b = alloca i64, align 8
  store i64 %x, ptr %a, align 8
  store i64 %y, ptr %b, align 8
  br label %loop
loop:
  %p = phi ptr [ %a, %entry ], [ %q, %loop ]
  %q = phi ptr [ %a, %entry ], [ %p, %loop ]
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

define i64 @non_swapping_backedge(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @non_swapping_backedge(
; CHECK: phi ptr
entry:
  %a = alloca i64, align 8
  %b = alloca i64, align 8
  store i64 %x, ptr %a, align 8
  store i64 %y, ptr %b, align 8
  br label %loop
loop:
  %p = phi ptr [ %a, %entry ], [ %q, %loop ]
  %q = phi ptr [ %b, %entry ], [ %q, %loop ]
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

; A preheader in an outer loop can observe the physical contents left by the
; previous execution of the inner loop, even if all direct uses are local to it.
define i64 @reentered_preheader(i64 %x, i64 %y, i1 %repeat) {
; CHECK-LABEL: @reentered_preheader(
; CHECK: phi ptr
; CHECK: phi ptr
entry:
  %a = alloca i64, align 8
  %b = alloca i64, align 8
  br label %preheader
preheader:
  %previous = load i64, ptr %a, align 8
  store i64 %x, ptr %a, align 8
  store i64 %y, ptr %b, align 8
  br label %loop
loop:
  %p = phi ptr [ %a, %preheader ], [ %q, %loop ]
  %q = phi ptr [ %b, %preheader ], [ %p, %loop ]
  %i = phi i32 [ 0, %preheader ], [ %next, %loop ]
  %pv = load i64, ptr %p, align 8
  %qv = load i64, ptr %q, align 8
  %sum = add i64 %pv, %qv
  store i64 %sum, ptr %p, align 8
  store i64 %pv, ptr %q, align 8
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, 3
  br i1 %done, label %exit, label %loop
exit:
  br i1 %repeat, label %preheader, label %return
return:
  ret i64 %previous
}

; Keep a defined byte next to a poison byte defined across the backedge.
define i8 @poison_bytes(i8 noundef %x) {
; CHECK-LABEL: @poison_bytes(
; CHECK: phi <16 x i8>
; CHECK: [[Q:%.*]] = phi <16 x i8>
; CHECK-NOT: bitcast
; CHECK: %byte = extractelement <16 x i8> [[Q]], i32 0
; CHECK-NEXT: %frozen = freeze i8 %byte
; CHECK-NOT: bitcast
; CHECK: ret i8 %frozen
entry:
  %a = alloca <2 x i64>, align 16
  %b = alloca <2 x i64>, align 16
  store <2 x i64> zeroinitializer, ptr %a, align 16
  store <2 x i64> zeroinitializer, ptr %b, align 16
  br label %loop
loop:
  %p = phi ptr [ %a, %entry ], [ %q, %loop ]
  %q = phi ptr [ %b, %entry ], [ %p, %loop ]
  %i = phi i32 [ 0, %entry ], [ %next, %loop ]
  %v = load <16 x i8>, ptr %q, align 16
  %partial = insertelement <16 x i8> <i8 5, i8 poison, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0, i8 0>, i8 %x, i32 0
  store <16 x i8> %partial, ptr %p, align 16
  %byte = extractelement <16 x i8> %v, i32 0
  %frozen = freeze i8 %byte
  store <2 x i64> zeroinitializer, ptr %q, align 16
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, 2
  br i1 %done, label %exit, label %loop
exit:
  ret i8 %frozen
}

define i64 @sub_byte_lanes(ptr %output, i64 %x, i64 %y, i32 %n) {
; CHECK-LABEL: @sub_byte_lanes(
; CHECK: phi ptr
; CHECK: phi ptr
entry:
  %a = alloca <64 x i1>, align 8
  %b = alloca <64 x i1>, align 8
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

define i256 @large_slots(ptr %output, i256 %x, i256 %y, i32 %n) {
; CHECK-LABEL: @large_slots(
; CHECK: phi ptr
; CHECK: phi ptr
entry:
  %a = alloca i256, align 8
  %b = alloca i256, align 8
  store i256 %x, ptr %a, align 8
  store i256 %y, ptr %b, align 8
  br label %loop
loop:
  %p = phi ptr [ %a, %entry ], [ %q, %loop ]
  %q = phi ptr [ %b, %entry ], [ %p, %loop ]
  %i = phi i32 [ 0, %entry ], [ %next, %loop ]
  %pv = load i256, ptr %p, align 8
  %qv = load i256, ptr %q, align 8
  %newp = add i256 %pv, %qv
  store i256 %newp, ptr %p, align 8
  store i256 %pv, ptr %q, align 8
  store i256 %newp, ptr %output, align 1
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, %n
  br i1 %done, label %exit, label %loop
exit:
  ret i256 %newp
}
