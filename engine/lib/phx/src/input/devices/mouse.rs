use glam::Vec2;
use tracing::warn;

use crate::input::*;

#[luajit_ffi_gen::luajit_ffi]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MouseControl {
    Left,
    Middle,
    Right,
    Forward,
    Back,
    X1,
    X2,
    DeltaX,
    DeltaY,
    ScrollX,
    ScrollY,
    ScrollPixelX,
    ScrollPixelY,
}

impl MouseControl {
    pub fn is_button(&self) -> bool {
        matches!(
            self,
            Self::Left
                | Self::Middle
                | Self::Right
                | Self::Forward
                | Self::Back
                | Self::X1
                | Self::X2
        )
    }

    pub fn is_axis(&self) -> bool {
        matches!(
            self,
            Self::DeltaX
                | Self::DeltaY
                | Self::ScrollX
                | Self::ScrollY
                | Self::ScrollPixelX
                | Self::ScrollPixelY
        )
    }
}

#[derive(Default)]
pub struct MouseState {
    control_state: ControlState,
    button_state: ButtonState<{ MouseControl::SIZE }>,
    axis_state: AxisState<{ MouseControl::SIZE }>,

    position: Vec2,
    in_window: bool,
    /// Raw motion events (`update_raw_delta`) have arrived: they are the
    /// mouse's movement from then on, and cursor moves no longer count.
    has_raw_motion: bool,
    /// The raw motion stream carries absolute coordinates rather than
    /// movement, so it is ignored and the cursor's own movement is used
    /// instead. See [`MouseState::update_raw_delta`].
    raw_motion_is_absolute: bool,
}

/// No mouse reports moving this far in a single packet (they arrive at up to
/// the polling rate, often 1000 Hz, so even a fast flick is a few hundred
/// pixels at most). A "delta" this large is an absolute coordinate.
const RAW_MOTION_SANITY_LIMIT: f32 = 2000.0;

impl MouseState {
    pub fn control_state(&self) -> &ControlState {
        &self.control_state
    }

    pub fn control_state_mut(&mut self) -> &mut ControlState {
        &mut self.control_state
    }

    pub fn reset(&mut self) {
        self.button_state.reset();
        self.axis_state.reset();

        // Zero per-frame delta axes so they don't persist into the next frame
        self.axis_state.zero(MouseControl::DeltaX as _);
        self.axis_state.zero(MouseControl::DeltaY as _);
        self.axis_state.zero(MouseControl::ScrollX as _);
        self.axis_state.zero(MouseControl::ScrollY as _);
        self.axis_state.zero(MouseControl::ScrollPixelX as _);
        self.axis_state.zero(MouseControl::ScrollPixelY as _);
    }

    pub fn update_button(&mut self, control: MouseControl, pressed: bool) -> bool {
        self.button_state.update(control as _, pressed)
            && self
                .axis_state
                .update(control as _, if pressed { 1.0 } else { 0.0 })
            && self.control_state.update()
    }

    // Scroll and movement are per-frame totals (zeroed in `reset`): a frame
    // can get several events, and setting the value would keep only the last.

    pub fn update_scroll_pixel(&mut self, x: f32, y: f32) -> bool {
        self.axis_state.add(MouseControl::ScrollPixelX as _, x)
            && self.axis_state.add(MouseControl::ScrollPixelY as _, y)
            && self.control_state.update()
    }

    pub fn update_scroll_line(&mut self, x: f32, y: f32) -> bool {
        self.axis_state.add(MouseControl::ScrollX as _, x)
            && self.axis_state.add(MouseControl::ScrollY as _, y)
            && self.control_state.update()
    }

    pub fn update_position(&mut self, x: f32, y: f32) -> bool {
        let prev_pos = self.position;

        self.position = Vec2::new(x, y);

        // Only where no raw motion arrives: a cursor held in the window (the
        // camera's grab) stops at its edge while the mouse keeps moving.
        if !self.has_raw_motion {
            self.axis_state
                .add(MouseControl::DeltaX as _, x - prev_pos.x);
            self.axis_state
                .add(MouseControl::DeltaY as _, y - prev_pos.y);
        }
        self.control_state.update()
    }

    pub fn update_in_window(&mut self, in_window: bool) -> bool {
        self.in_window = in_window;

        self.control_state.update()
    }

    /// The device's own movement, independent of the cursor. Windows sends
    /// one event per mouse report (up to the mouse's polling rate, often
    /// 1000 Hz), so many arrive per frame: they add up.
    ///
    /// Not every mouse reports movement. A remote desktop session, a virtual
    /// machine's pointer, a graphics tablet and some KVM switches report
    /// *absolute* position instead, flagged `MOUSE_MOVE_ABSOLUTE` and scaled
    /// to 0..65535 across the virtual desktop. winit 0.30 tests that flag
    /// with `has_flag(usFlags, MOUSE_MOVE_RELATIVE)`, and `MOUSE_MOVE_RELATIVE`
    /// is zero, so `usFlags & 0 == 0` holds for every packet: absolute
    /// coordinates arrive as `DeviceEvent::MouseMotion` deltas. The smallest
    /// movement then reads as tens of thousands of pixels, which sends
    /// anything steering by mouse movement -- the first-person and orbit
    /// cameras, first-person flight -- spinning.
    ///
    /// A packet beyond any real mouse's reach says the stream is absolute.
    /// From then on it is ignored and the cursor's own movement
    /// ([`MouseState::update_position`]) is the mouse's movement, which the
    /// window system reports correctly in those sessions.
    pub fn update_raw_delta(&mut self, dx: f32, dy: f32) -> bool {
        if self.raw_motion_is_absolute {
            return false;
        }
        if dx.abs() > RAW_MOTION_SANITY_LIMIT || dy.abs() > RAW_MOTION_SANITY_LIMIT {
            warn!(
                "Raw mouse motion of ({dx}, {dy}) is an absolute position, not movement \
                 (a remote desktop session or a virtual pointer): using the cursor's \
                 movement from here on."
            );
            self.raw_motion_is_absolute = true;
            self.has_raw_motion = false;
            // Whatever this frame accumulated before the stream was found out
            self.axis_state.zero(MouseControl::DeltaX as _);
            self.axis_state.zero(MouseControl::DeltaY as _);
            return false;
        }
        self.has_raw_motion = true;
        self.axis_state.add(MouseControl::DeltaX as _, dx)
            && self.axis_state.add(MouseControl::DeltaY as _, dy)
            && self.control_state.update()
    }
}

#[luajit_ffi_gen::luajit_ffi]
impl MouseState {
    pub fn value(&self, control: MouseControl) -> f32 {
        // TODO: should MouseControl be splitted to MouseButton and MouseAxis? This will require changes in Lua scripts
        if control.is_axis() {
            self.axis_state.value(control as _)
        } else if self.button_state.is_down(control as _) {
            1.0
        } else {
            0.0
        }
    }

    pub fn is_pressed(&self, control: MouseControl) -> bool {
        self.button_state.is_pressed(control as _)
    }

    pub fn is_down(&self, control: MouseControl) -> bool {
        self.button_state.is_down(control as _)
    }

    pub fn is_released(&self, control: MouseControl) -> bool {
        self.button_state.is_released(control as _)
    }

    pub fn delta(&self) -> Vec2 {
        let x = self.axis_state.value(MouseControl::DeltaX as _);
        let y = self.axis_state.value(MouseControl::DeltaY as _);

        Vec2::new(x, y)
    }

    pub fn scroll(&self) -> Vec2 {
        let x = self.axis_state.value(MouseControl::ScrollX as _);
        let y = self.axis_state.value(MouseControl::ScrollY as _);

        Vec2::new(x, y)
    }

    pub fn scroll_pixel(&self) -> Vec2 {
        let x = self.axis_state.value(MouseControl::ScrollPixelX as _);
        let y = self.axis_state.value(MouseControl::ScrollPixelY as _);

        Vec2::new(x, y)
    }

    pub fn position(&self) -> Vec2 {
        self.position
    }

    pub fn in_window(&self) -> bool {
        self.in_window
    }
}
