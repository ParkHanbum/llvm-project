; RUN: opt -passes=instcombine -S < %s | FileCheck %s --check-prefixes=CHECK,LITTLE
; RUN: opt -passes=instcombine -S -data-layout="E" < %s | FileCheck %s --check-prefixes=CHECK,BIG

define i16 @trunc_i32_lshr16(ptr %p) {
; LITTLE-LABEL: @trunc_i32_lshr16(
; LITTLE-NEXT:    [[TMP1:%.*]] = getelementptr inbounds nuw i8, ptr [[P:%.*]], i64 2
; LITTLE-NEXT:    [[X:%.*]] = load i16, ptr [[TMP1]], align 2
; LITTLE-NEXT:    ret i16 [[X]]
;
; BIG-LABEL: @trunc_i32_lshr16(
; BIG-NEXT:    [[X:%.*]] = load i16, ptr [[P:%.*]], align 4
; BIG-NEXT:    ret i16 [[X]]
;
  %x = load i32, ptr %p, align 4
  %s = lshr i32 %x, 16
  %t = trunc i32 %s to i16
  ret i16 %t
}

define i8 @trunc_i32_lshr24(ptr %p) {
; LITTLE-LABEL: @trunc_i32_lshr24(
; LITTLE-NEXT:    [[TMP1:%.*]] = getelementptr inbounds nuw i8, ptr [[P:%.*]], i64 3
; LITTLE-NEXT:    [[X:%.*]] = load i8, ptr [[TMP1]], align 1
; LITTLE-NEXT:    ret i8 [[X]]
;
; BIG-LABEL: @trunc_i32_lshr24(
; BIG-NEXT:    [[X:%.*]] = load i8, ptr [[P:%.*]], align 4
; BIG-NEXT:    ret i8 [[X]]
;
  %x = load i32, ptr %p, align 4
  %s = lshr i32 %x, 24
  %t = trunc i32 %s to i8
  ret i8 %t
}

define i64 @zext_i32_lshr16(ptr %p) {
; LITTLE-LABEL: @zext_i32_lshr16(
; LITTLE-NEXT:    [[TMP1:%.*]] = getelementptr inbounds nuw i8, ptr [[P:%.*]], i64 2
; LITTLE-NEXT:    [[X:%.*]] = load i16, ptr [[TMP1]], align 2
; LITTLE-NEXT:    [[Z:%.*]] = zext i16 [[X]] to i64
; LITTLE-NEXT:    ret i64 [[Z]]
;
; BIG-LABEL: @zext_i32_lshr16(
; BIG-NEXT:    [[X:%.*]] = load i16, ptr [[P:%.*]], align 4
; BIG-NEXT:    [[Z:%.*]] = zext i16 [[X]] to i64
; BIG-NEXT:    ret i64 [[Z]]
;
  %x = load i32, ptr %p, align 4
  %s = lshr i32 %x, 16
  %z = zext i32 %s to i64
  ret i64 %z
}

define i1 @icmp_i32_lshr24(ptr %p) {
; LITTLE-LABEL: @icmp_i32_lshr24(
; LITTLE-NEXT:    [[TMP1:%.*]] = getelementptr inbounds nuw i8, ptr [[P:%.*]], i64 3
; LITTLE-NEXT:    [[X:%.*]] = load i8, ptr [[TMP1]], align 1
; LITTLE-NEXT:    [[C:%.*]] = icmp eq i8 [[X]], 42
; LITTLE-NEXT:    ret i1 [[C]]
;
; BIG-LABEL: @icmp_i32_lshr24(
; BIG-NEXT:    [[X:%.*]] = load i8, ptr [[P:%.*]], align 4
; BIG-NEXT:    [[C:%.*]] = icmp eq i8 [[X]], 42
; BIG-NEXT:    ret i1 [[C]]
;
  %x = load i32, ptr %p, align 4
  %s = lshr i32 %x, 24
  %c = icmp eq i32 %s, 42
  ret i1 %c
}

define i32 @switch_i32_lshr24(ptr %p) {
; LITTLE-LABEL: @switch_i32_lshr24(
; LITTLE-NEXT:  entry:
; LITTLE-NEXT:    [[TMP1:%.*]] = getelementptr inbounds nuw i8, ptr [[P:%.*]], i64 3
; LITTLE-NEXT:    [[X:%.*]] = load i8, ptr [[TMP1]], align 1
; LITTLE-NEXT:    switch i8 [[X]], label [[DEFAULT:%.*]] [
; LITTLE-NEXT:      i8 1, label [[CASE1:%.*]]
; LITTLE-NEXT:      i8 2, label [[CASE2:%.*]]
; LITTLE-NEXT:    ]
; LITTLE:       default:
; LITTLE-NEXT:    ret i32 0
; LITTLE:       case1:
; LITTLE-NEXT:    ret i32 1
; LITTLE:       case2:
; LITTLE-NEXT:    ret i32 2
;
; BIG-LABEL: @switch_i32_lshr24(
; BIG-NEXT:  entry:
; BIG-NEXT:    [[X:%.*]] = load i8, ptr [[P:%.*]], align 4
; BIG-NEXT:    switch i8 [[X]], label [[DEFAULT:%.*]] [
; BIG-NEXT:      i8 1, label [[CASE1:%.*]]
; BIG-NEXT:      i8 2, label [[CASE2:%.*]]
; BIG-NEXT:    ]
; BIG:       default:
; BIG-NEXT:    ret i32 0
; BIG:       case1:
; BIG-NEXT:    ret i32 1
; BIG:       case2:
; BIG-NEXT:    ret i32 2
;
entry:
  %x = load i32, ptr %p, align 4
  %s = lshr i32 %x, 24
  switch i32 %s, label %default [
    i32 1, label %case1
    i32 2, label %case2
  ]

default:
  ret i32 0

case1:
  ret i32 1

case2:
  ret i32 2
}

define i24 @negative_i24_width(ptr %p) {
; CHECK-LABEL: @negative_i24_width(
; CHECK-NEXT:    [[X:%.*]] = load i32, ptr [[P:%.*]], align 4
; CHECK-NEXT:    [[S:%.*]] = lshr i32 [[X]], 8
; CHECK-NEXT:    [[T:%.*]] = trunc nuw i32 [[S]] to i24
; CHECK-NEXT:    ret i24 [[T]]
;
  %x = load i32, ptr %p, align 4
  %s = lshr i32 %x, 8
  %t = trunc i32 %s to i24
  ret i24 %t
}

define i16 @negative_volatile(ptr %p) {
; CHECK-LABEL: @negative_volatile(
; CHECK-NEXT:    [[X:%.*]] = load volatile i32, ptr [[P:%.*]], align 4
; CHECK-NEXT:    [[S:%.*]] = lshr i32 [[X]], 16
; CHECK-NEXT:    [[T:%.*]] = trunc nuw i32 [[S]] to i16
; CHECK-NEXT:    ret i16 [[T]]
;
  %x = load volatile i32, ptr %p, align 4
  %s = lshr i32 %x, 16
  %t = trunc i32 %s to i16
  ret i16 %t
}

define i16 @negative_exact(ptr %p) {
; CHECK-LABEL: @negative_exact(
; CHECK-NEXT:    [[X:%.*]] = load i32, ptr [[P:%.*]], align 4
; CHECK-NEXT:    [[S:%.*]] = lshr exact i32 [[X]], 16
; CHECK-NEXT:    [[T:%.*]] = trunc nuw i32 [[S]] to i16
; CHECK-NEXT:    ret i16 [[T]]
;
  %x = load i32, ptr %p, align 4
  %s = lshr exact i32 %x, 16
  %t = trunc i32 %s to i16
  ret i16 %t
}

define i32 @negative_load_multiuse(ptr %p) {
; CHECK-LABEL: @negative_load_multiuse(
; CHECK-NEXT:    [[X:%.*]] = load i32, ptr [[P:%.*]], align 4
; CHECK-NEXT:    [[S:%.*]] = lshr i32 [[X]], 16
; CHECK-NEXT:    [[R:%.*]] = add i32 [[S]], [[X]]
; CHECK-NEXT:    ret i32 [[R]]
;
  %x = load i32, ptr %p, align 4
  %s = lshr i32 %x, 16
  %r = add i32 %s, %x
  ret i32 %r
}
