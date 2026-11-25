#![allow(unsafe_code)] // TODO: remove (reads C strings handed over by Lua)

use std::ffi::CString;

pub trait ConvertIntoString {
    fn as_str(&self) -> &str;

    fn as_string(&self) -> String {
        self.as_str().to_string()
    }

    fn as_cstring(&self) -> CString;
}

impl ConvertIntoString for *const libc::c_char {
    fn as_str(&self) -> &str {
        if self.is_null() {
            return "<null>";
        }

        // SAFETY: not null (checked above); the caller hands over a
        // NUL-terminated string that outlives the returned &str.
        let bytes = unsafe { std::ffi::CStr::from_ptr(*self).to_bytes() };
        // Strings from Lua are not guaranteed UTF-8: from_utf8_unchecked on
        // them was undefined behaviour
        std::str::from_utf8(bytes).unwrap_or("<invalid utf-8>")
    }

    fn as_cstring(&self) -> CString {
        if self.is_null() {
            return CString::default();
        }
        // SAFETY: not null (checked above); NUL-terminated, as for as_str.
        let cstr = unsafe { std::ffi::CStr::from_ptr(*self) };

        cstr.into()
    }
}
