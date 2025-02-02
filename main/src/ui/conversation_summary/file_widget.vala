using Gee;
using Gdk;
using Gtk;
using Pango;

using Dino.Entities;

namespace Dino.Ui.ConversationSummary {

public class FileWidget : Box {

    enum State {
        IMAGE,
        DEFAULT
    }

    private const int MAX_HEIGHT = 300;
    private const int MAX_WIDTH = 600;

    private StreamInteractor stream_interactor;
    private FileTransfer file_transfer;
    private State state;

    // default box
    private Box main_box;
    private string? icon_name;
    private Image content_type_image;
    private Image download_image;
    private Spinner spinner;
    private Label mime_label;
    private Stack image_stack;

    private Widget content;

    private bool pointer_inside = false;

    public FileWidget(StreamInteractor stream_interactor, FileTransfer file_transfer) {
        this.stream_interactor = stream_interactor;
        this.file_transfer = file_transfer;

        if (show_image()) {
            content =  getImageWidget(file_transfer);
            if (content != null) {
                this.state = State.IMAGE;
                this.add(content);
                return;
            }
        }

        content = getDefaultWidget(file_transfer);
        this.state = State.DEFAULT;
        this.add(content);
    }

    private Widget? getImageWidget(FileTransfer file_transfer) {
        Image image = new Image() { halign=Align.START, visible = true };
        Gdk.Pixbuf pixbuf;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file_transfer.get_file().get_path());
        } catch (Error error) {
            warning("Can't load picture %s", file_transfer.get_file().get_path());
            return null;
        }

        pixbuf = pixbuf.apply_embedded_orientation();

        int max_scaled_height = MAX_HEIGHT * image.scale_factor;
        if (pixbuf.height > max_scaled_height) {
            pixbuf = pixbuf.scale_simple((int) ((double) max_scaled_height / pixbuf.height * pixbuf.width), max_scaled_height, Gdk.InterpType.BILINEAR);
        }
        int max_scaled_width = MAX_WIDTH * image.scale_factor;
        if (pixbuf.width > max_scaled_width) {
            pixbuf = pixbuf.scale_simple(max_scaled_width, (int) ((double) max_scaled_width / pixbuf.width * pixbuf.height), Gdk.InterpType.BILINEAR);
        }
        pixbuf = crop_corners(pixbuf, 3 * image.get_scale_factor());
        Util.image_set_from_scaled_pixbuf(image, pixbuf);
        Util.force_css(image, "* { box-shadow: 0px 0px 2px 0px rgba(0,0,0,0.1); margin: 2px; border-radius: 3px; }");

        Builder builder = new Builder.from_resource("/im/dino/Dino/conversation_summary/image_toolbar.ui");
        Widget toolbar = builder.get_object("main") as Widget;
        Util.force_background(toolbar, "rgba(0, 0, 0, 0.5)");
        Util.force_css(toolbar, "* { padding: 3px; border-radius: 3px; }");

        Label url_label = builder.get_object("url_label") as Label;
        Util.force_color(url_label, "#eee");

        if (file_transfer.file_name != null && file_transfer.file_name != "") {
            string caption = file_transfer.file_name;
            url_label.label = caption;
        } else {
            url_label.visible = false;
        }

        Image open_image = builder.get_object("open_image") as Image;
        Util.force_css(open_image, "*:not(:hover) { color: #eee; }");
        Button open_button = builder.get_object("open_button") as Button;
        Util.force_css(open_button, "*:hover { background-color: rgba(255,255,255,0.3); border-color: transparent; }");
        open_button.clicked.connect(() => {
            try{
                AppInfo.launch_default_for_uri(file_transfer.get_file().get_uri(), null);
            } catch (Error err) {
                info("Could not to open file://%s: %s", file_transfer.get_file().get_path(), err.message);
            }
        });

        Revealer toolbar_revealer = new Revealer() { transition_type=RevealerTransitionType.CROSSFADE, transition_duration=400, visible=true };
        toolbar_revealer.add(toolbar);

        Grid grid = new Grid() { visible=true };
        grid.attach(toolbar_revealer, 0, 0, 1, 1);
        grid.attach(image, 0, 0, 1, 1);

        EventBox event_box = new EventBox() { margin_top=5, halign=Align.START, visible=true };
        event_box.events = EventMask.POINTER_MOTION_MASK;
        event_box.add(grid);
        event_box.enter_notify_event.connect(() => { toolbar_revealer.reveal_child = true; return false; });
        event_box.leave_notify_event.connect(() => { toolbar_revealer.reveal_child = false; return false; });

        return event_box;
    }

    private static Gdk.Pixbuf crop_corners(Gdk.Pixbuf pixbuf, double radius = 3) {
        Cairo.Context ctx = new Cairo.Context(new Cairo.ImageSurface(Cairo.Format.ARGB32, pixbuf.width, pixbuf.height));
        Gdk.cairo_set_source_pixbuf(ctx, pixbuf, 0, 0);
        double degrees = Math.PI / 180.0;
        ctx.new_sub_path();
        ctx.arc(pixbuf.width - radius, radius, radius, -90 * degrees, 0 * degrees);
        ctx.arc(pixbuf.width - radius, pixbuf.height - radius, radius, 0 * degrees, 90 * degrees);
        ctx.arc(radius, pixbuf.height - radius, radius, 90 * degrees, 180 * degrees);
        ctx.arc(radius, radius, radius, 180 * degrees, 270 * degrees);
        ctx.close_path();
        ctx.clip();
        ctx.paint();
        return Gdk.pixbuf_get_from_surface(ctx.get_target(), 0, 0, pixbuf.width, pixbuf.height);
    }

    private Widget getDefaultWidget(FileTransfer file_transfer) {
        main_box = new Box(Orientation.HORIZONTAL, 4) { halign=Align.FILL, hexpand=true, visible=true };
        icon_name = ContentType.get_generic_icon_name(file_transfer.mime_type ?? "application/octet-stream");
        content_type_image = new Image.from_icon_name(icon_name + "-symbolic", IconSize.DND) { visible=true };
        download_image = new Image.from_icon_name("folder-download-symbolic", IconSize.MENU) { visible=true };
        spinner = new Spinner() { active=true, visible=true };

        EventBox stack_event_box = new EventBox() { visible=true };
        image_stack = new Stack() { transition_type = StackTransitionType.CROSSFADE, transition_duration=50, valign=Align.CENTER, visible=true };
        image_stack.add_named(download_image, "download_image");
        image_stack.add_named(spinner, "spinner");
        image_stack.add_named(content_type_image, "content_type_image");
        stack_event_box.add(image_stack);

        main_box.add(stack_event_box);

        Box right_box = new Box(Orientation.VERTICAL, 0) { hexpand=true, visible=true };
        Label name_label = new Label(file_transfer.file_name) { ellipsize=EllipsizeMode.MIDDLE, max_width_chars=1, hexpand=true, xalign=0, yalign=0, visible=true};
        right_box.add(name_label);

        EventBox mime_label_event_box = new EventBox() { visible=true };
        mime_label = new Label("") { use_markup=true, xalign=0, yalign=1, visible=true};

        mime_label_event_box.add(mime_label);
        mime_label.get_style_context().add_class("dim-label");

        right_box.add(mime_label_event_box);
        main_box.add(right_box);

        EventBox event_box = new EventBox() { margin_top=5, width_request=500, halign=Align.START, visible=true };
        event_box.get_style_context().add_class("file-box-outer");
        event_box.add(main_box);
        main_box.get_style_context().add_class("file-box");

        event_box.enter_notify_event.connect((event) => {
            pointer_inside = true;
            Timeout.add(20, () => {
                if (pointer_inside) {
                    event.get_window().set_cursor(new Cursor.for_display(Gdk.Display.get_default(), CursorType.HAND2));
                    if (file_transfer.state == FileTransfer.State.NOT_STARTED) {
                        image_stack.set_visible_child_name("download_image");
                    } else if (file_transfer.state == FileTransfer.State.COMPLETE) {
                        content_type_image.opacity = 1;
                    }
                }
                return false;
            });
            return false;
        });
        stack_event_box.enter_notify_event.connect((event) => { pointer_inside = true; return false; });
        mime_label_event_box.enter_notify_event.connect((event) => { pointer_inside = true; return false; });
        mime_label.enter_notify_event.connect((event) => { pointer_inside = true; return false; });
        event_box.leave_notify_event.connect((event) => {
            pointer_inside = false;
            Timeout.add(20, () => {
                if (!pointer_inside) {
                    event.get_window().set_cursor(new Cursor.for_display(Gdk.Display.get_default(), CursorType.XTERM));
                    if (file_transfer.state == FileTransfer.State.NOT_STARTED) {
                        image_stack.set_visible_child_name("content_type_image");
                    } else if (file_transfer.state == FileTransfer.State.COMPLETE) {
                        content_type_image.opacity = 0.5;
                    }
                }
                return false;
            });
            return false;
        });
        stack_event_box.leave_notify_event.connect((event) => { pointer_inside = true; return false; });
        mime_label_event_box.leave_notify_event.connect((event) => { pointer_inside = true; return false; });
        mime_label.leave_notify_event.connect((event) => { pointer_inside = true; return false; });
        event_box.button_release_event.connect((event_button) => {
            switch (file_transfer.state) {
                case FileTransfer.State.COMPLETE:
                    if (event_button.button == 1) {
                        try{
                            AppInfo.launch_default_for_uri(file_transfer.get_file().get_uri(), null);
                        } catch (Error err) {
                            print("Tried to open " + file_transfer.get_file().get_path());
                        }
                    }
                    break;
                case FileTransfer.State.NOT_STARTED:
                    stream_interactor.get_module(FileManager.IDENTITY).download_file.begin(file_transfer);
                    break;
            }
            return false;
        });

        main_box.events = EventMask.POINTER_MOTION_MASK;
        content_type_image.events = EventMask.POINTER_MOTION_MASK;
        download_image.events = EventMask.POINTER_MOTION_MASK;
        spinner.events = EventMask.POINTER_MOTION_MASK;
        image_stack.events = EventMask.POINTER_MOTION_MASK;
        right_box.events = EventMask.POINTER_MOTION_MASK;
        name_label.events = EventMask.POINTER_MOTION_MASK;
        mime_label.events = EventMask.POINTER_MOTION_MASK;
        event_box.events = EventMask.POINTER_MOTION_MASK;
        mime_label.events = EventMask.POINTER_MOTION_MASK;
        mime_label_event_box.events = EventMask.POINTER_MOTION_MASK;

        file_transfer.notify["path"].connect(update_file_info);
        file_transfer.notify["state"].connect(update_file_info);
        file_transfer.notify["mime-type"].connect(update_file_info);
        update_file_info();

        return event_box;
    }

    private void update_file_info() {
        if (file_transfer.state == FileTransfer.State.COMPLETE && show_image() && state != State.IMAGE) {
            this.remove(content);
            this.add(getImageWidget(file_transfer));
            state = State.IMAGE;
        }

        content_type_image.opacity = 0.5;

        var mime_split = (file_transfer.mime_type ?? "").split("/");
        var mime_caps = mime_split.length == 2 ? mime_split[1].up() : file_transfer.mime_type;

        switch (file_transfer.state) {
            case FileTransfer.State.COMPLETE:
                mime_label.label = "<span size='small'>" + _("%s file").printf(mime_caps) + "</span>";
                image_stack.set_visible_child_name("content_type_image");
                break;
            case FileTransfer.State.IN_PROGRESS:
                mime_label.label = "<span size='small'>" + _("Downloading %s…").printf(get_size_string(file_transfer.size)) + "</span>";
                image_stack.set_visible_child_name("spinner");
                break;
            case FileTransfer.State.NOT_STARTED:
                if (mime_caps != null) {
                    mime_label.label = "<span size='small'>" + _("%s file offered: %s").printf(mime_caps, get_size_string(file_transfer.size)) + "</span>";
                } else if (file_transfer.size != -1) {
                    mime_label.label = "<span size='small'>" + _("File offered: %s").printf(get_size_string(file_transfer.size)) + "</span>";
                } else {
                    mime_label.label = "<span size='small'>" + _("File offered") + "</span>";
                }
                image_stack.set_visible_child_name("content_type_image");
                break;
            case FileTransfer.State.FAILED:
                mime_label.label = "<span size='small' foreground=\"#f44336\">" + _("File transfer failed") + "</span>";
                image_stack.set_visible_child_name("content_type_image");
                break;
        }
    }

    private static string get_size_string(int size) {
        if (size < 1024) {
            return @"$(size) B";
        } else if (size < 1000 * 1000) {
            return @"$(size / 1000) kB";
        } else if (size < 1000 * 1000 * 1000) {
            return @"$(size / 1000  / 1000) MB";
        } else {
            return @"$(size  / 1000  / 1000  / 1000) GB";
        }
    }

    private bool show_image() {
        if (file_transfer.mime_type == null || file_transfer.state != FileTransfer.State.COMPLETE) return false;

        foreach (PixbufFormat pixbuf_format in Pixbuf.get_formats()) {
            foreach (string mime_type in pixbuf_format.get_mime_types()) {
                if (mime_type == file_transfer.mime_type) {
                    return true;
                }
            }
        }
        return false;
    }
}

}
