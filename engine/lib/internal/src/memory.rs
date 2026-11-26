#![allow(clippy::missing_safety_doc)] // This file will be removed after refactoring
#![allow(unsafe_code)] // TODO: remove (C-style allocation for the Lua side)

#[inline]
pub unsafe extern "C" fn mem_alloc(size: usize) -> *mut libc::c_void {
    unsafe { libc::malloc(size) }
}

#[inline]
pub unsafe extern "C" fn mem_free(ptr: *const libc::c_void) {
    unsafe { libc::free(ptr.cast_mut()) };
}

#[inline]
pub unsafe extern "C" fn mem_realloc(ptr: *mut libc::c_void, new_size: usize) -> *mut libc::c_void {
    unsafe { libc::realloc(ptr, new_size) }
}

#[inline]
pub unsafe extern "C" fn mem_zero(dst: *mut libc::c_void, size: usize) {
    unsafe { libc::memset(dst, 0, size) };
}
