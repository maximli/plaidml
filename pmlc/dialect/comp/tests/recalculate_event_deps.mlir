// RUN: pmlc-opt --comp-recalc-event-deps --split-input-file %s | FileCheck %s -check-prefix=CHECK -check-prefix=SAFE
// RUN: pmlc-opt --comp-recalc-event-deps="safe-dealloc=false" --split-input-file %s | FileCheck %s -check-prefix=CHECK -check-prefix=UNSAFE

// CHECK-LABEL: func @chain_of_two
//       CHECK:   %[[EV1:.*]] = comp.schedule_write %{{.*}} to %{{.*}} on %{{.*}} :
//   CHECK-NOT:   comp.wait
//       CHECK:   %[[EV2:.*]] = comp.schedule_read %{{.*}} from %{{.*}} on %{{.*}} wait for %[[EV1]] :
//       CHECK:   comp.wait %[[EV2]]
func @chain_of_two(%env: !comp.execenv<ocl:0,(11)>, %host: memref<2x3xf32>) {
  %mem = comp.alloc %env : (!comp.execenv<ocl:0,(11)>) -> memref<2x3xf32, 11>
  %ev1 = comp.schedule_write %host to %mem on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev1 : !comp.event<ocl>
  %ev2 = comp.schedule_read %host from %mem on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev2 : !comp.event<ocl>
  comp.dealloc %env %mem : (!comp.execenv<ocl:0,(11)>, memref<2x3xf32, 11>) -> ()
  return
}

// -----

module attributes {gpu.container_module} {
  // CHECK-LABEL: func @schedule_func
  //       CHECK:   %[[EV1:.*]] = comp.schedule_write %{{.*}} to %{{.*}} on %{{.*}} :
  //   CHECK-NOT:   comp.wait
  //       CHECK:   %[[EV2:.*]] = comp.schedule_compute
  //  CHECK-SAME:   %[[EV1]]
  //   CHECK-NOT:   comp.wait
  //       CHECK:   %[[EV3:.*]] = comp.schedule_read %{{.*}} from %{{.*}} on %{{.*}} wait for
  //  CHECK-SAME:     %[[EV2]]
  //       CHECK:   comp.wait %[[EV3]]
  func @schedule_func(%env : !comp.execenv<ocl:0,(11)>, %host: memref<2x3xf32>) {
    %c1 = constant 1 : index
    %mem = comp.alloc %env : (!comp.execenv<ocl:0,(11)>) -> memref<2x3xf32, 11>
    %ev1 = comp.schedule_write %host to %mem on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
    comp.wait %ev1 : !comp.event<ocl>
    %k = comp.create_kernel on %env {kernelFunc = @gpu_module::@kernel} : (!comp.execenv<ocl:0,(11)>) -> !comp.kernel
    %ev2 = comp.schedule_compute %k grid %c1, %c1, %c1 block %c1, %c1, %c1 args %mem on %env : (!comp.execenv<ocl:0,(11)>, !comp.kernel, index, index, index, index, index, index, memref<2x3xf32, 11>) -> !comp.event<ocl>
    comp.wait %ev2 : !comp.event<ocl>
    %ev3 = comp.schedule_read %host from %mem on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
    comp.wait %ev3 : !comp.event<ocl>
    comp.destroy_kernel %k on %env : (!comp.execenv<ocl:0,(11)>, !comp.kernel) -> ()
    comp.dealloc %env %mem : (!comp.execenv<ocl:0,(11)>, memref<2x3xf32, 11>) -> ()
    return
  }

  gpu.module @gpu_module {
    gpu.func @kernel(%arg0: memref<2x3xf32, 11>) kernel attributes {spv.entry_point_abi = {local_size = dense<[1, 1, 1]> : vector<3xi32>}} {
      gpu.return
    }
  }
}

// -----

// CHECK-LABEL: func @external_event
//  CHECK-SAME:     %[[EXT:[a-zA-Z0-9]*]]: !comp.event
//       CHECK:   %[[EV1:.*]] = comp.schedule_write %{{.*}} to %{{.*}} on %{{.*}} :
//   CHECK-NOT:   comp.wait
//       CHECK:   %[[EV2:.*]] = comp.schedule_read %{{.*}} from %{{.*}} on {{.*}} wait for
//   CHECK-DAG:     %[[EV1]]
//   CHECK-DAG:     %[[EXT]]
//       CHECK:   comp.wait %[[EV2]]
func @external_event(%env : !comp.execenv<ocl:0,(11)>, %host: memref<2x3xf32>, %ext: !comp.event<ocl>) {
  %mem = comp.alloc %env : (!comp.execenv<ocl:0,(11)>) -> memref<2x3xf32, 11>
  %ev1 = comp.schedule_write %host to %mem on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev1 : !comp.event<ocl>
  %ev2 = comp.schedule_read %host from %mem on %env wait for %ext : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>, !comp.event<ocl>) -> !comp.event<ocl>
  comp.wait %ev2 : !comp.event<ocl>
  comp.dealloc %env %mem : (!comp.execenv<ocl:0,(11)>, memref<2x3xf32, 11>) -> ()
  return
}

// -----

// CHECK-LABEL: func @external_wait
//  CHECK-SAME:     %[[EXT:[a-zA-Z0-9]*]]: !comp.event
//       CHECK:   %[[EV1:.*]] = comp.schedule_write %{{.*}} to %{{.*}} on %{{.*}} :
//       CHECK:   comp.wait %[[EXT]] :
//       CHECK:   %[[EV2:.*]] = comp.schedule_read %{{.*}} from %{{.*}} on {{.*}} wait for %[[EV1]] :
//       CHECK:   comp.wait %[[EV2]]
func @external_wait(%env : !comp.execenv<ocl:0,(11)>, %host: memref<2x3xf32>, %ext: !comp.event<ocl>) {
  %mem = comp.alloc %env : (!comp.execenv<ocl:0,(11)>) -> memref<2x3xf32, 11>
  %ev1 = comp.schedule_write %host to %mem on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev1, %ext : !comp.event<ocl>, !comp.event<ocl>
  %ev2 = comp.schedule_read %host from %mem on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev2 : !comp.event<ocl>
  comp.dealloc %env %mem : (!comp.execenv<ocl:0,(11)>, memref<2x3xf32, 11>) -> ()
  return
}

// -----

// CHECK-LABEL: func @destroy_execenv
//       CHECK:   %[[EV1:.*]] = comp.schedule_write %{{.*}} to %{{.*}} on %{{.*}} :
//   CHECK-NOT:   comp.wait
//       CHECK:   %[[EV2:.*]] = comp.schedule_read %{{.*}} from %{{.*}} on {{.*}} wait for %[[EV1]] :
//       CHECK:   comp.wait %[[EV2]]
//       CHECK:   comp.destroy_execenv
//       CHECK:   %[[EV3:.*]] = comp.schedule_write %{{.*}} to %{{.*}} on %{{.*}} :
//   CHECK-NOT:   comp.wait
//       CHECK:   %[[EV4:.*]] = comp.schedule_read %{{.*}} from %{{.*}} on {{.*}} wait for %[[EV3]] :
//       CHECK:   comp.wait %[[EV4]]
//       CHECK:   comp.destroy_execenv
func @destroy_execenv(%dev : !comp.device, %host: memref<2x3xf32>) {
  %env1 = comp.create_execenv %dev : (!comp.device) -> !comp.execenv<ocl:0,(11)>
  %mem1 = comp.alloc %env1 : (!comp.execenv<ocl:0,(11)>) -> memref<2x3xf32, 11>
  %ev1 = comp.schedule_write %host to %mem1 on %env1 : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev1 : !comp.event<ocl>
  %ev2 = comp.schedule_read %host from %mem1 on %env1 : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.destroy_execenv %env1 : !comp.execenv<ocl:0,(11)>

  %env2 = comp.create_execenv %dev : (!comp.device) -> !comp.execenv<ocl:0,(11)>
  %mem2 = comp.alloc %env2 : (!comp.execenv<ocl:0,(11)>) -> memref<2x3xf32, 11>
  %ev3 = comp.schedule_write %host to %mem2 on %env2 : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev3 : !comp.event<ocl>
  %ev4 = comp.schedule_read %host from %mem2 on %env2 : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.destroy_execenv %env2 : !comp.execenv<ocl:0,(11)>
  return
}

// -----

// CHECK-LABEL: func @middle_dealloc
//       CHECK:   %[[EV1:.*]] = comp.schedule_write %{{.*}} to %{{.*}} on %{{.*}} :
//   CHECK-NOT:   comp.wait
//       CHECK:   %[[EV2:.*]] = comp.schedule_read %{{.*}} from %{{.*}} on {{.*}} wait for %[[EV1]] :
//        SAFE:   comp.wait %[[EV2]]
//  UNSAFE-NOT:   comp.wait
//       CHECK:   comp.dealloc
//       CHECK:   %[[EV3:.*]] = comp.schedule_write %{{.*}} to %{{.*}} on %{{.*}} :
//   CHECK-NOT:   comp.wait
//       CHECK:   %[[EV4:.*]] = comp.schedule_read %{{.*}} from %{{.*}} on {{.*}} wait for %[[EV3]] :
//        SAFE:   comp.wait %[[EV4]]
//  UNSAFE-NOT:   comp.wait
//       CHECK:   comp.dealloc
//      UNSAFE:   comp.wait
//  UNSAFE-DAG:     %[[EV4]]
//  UNSAFE-DAG:     %[[EV2]]
func @middle_dealloc(%env : !comp.execenv<ocl:0,(11)>, %host1: memref<2x3xf32>, %host2: memref<2x3xf32>) {
  %mem1 = comp.alloc %env : (!comp.execenv<ocl:0,(11)>) -> memref<2x3xf32, 11>
  %ev1 = comp.schedule_write %host1 to %mem1 on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev1 : !comp.event<ocl>
  %ev2 = comp.schedule_read %host1 from %mem1 on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev2 : !comp.event<ocl>
  comp.dealloc %env %mem1 : (!comp.execenv<ocl:0,(11)>, memref<2x3xf32, 11>) -> ()

  %mem2 = comp.alloc %env : (!comp.execenv<ocl:0,(11)>) -> memref<2x3xf32, 11>
  %ev3 = comp.schedule_write %host2 to %mem2 on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev3 : !comp.event<ocl>
  %ev4 = comp.schedule_read %host2 from %mem2 on %env : (memref<2x3xf32>, memref<2x3xf32, 11>, !comp.execenv<ocl:0,(11)>) -> !comp.event<ocl>
  comp.wait %ev4 : !comp.event<ocl>
  comp.dealloc %env %mem2 : (!comp.execenv<ocl:0,(11)>, memref<2x3xf32, 11>) -> ()
  return
}
