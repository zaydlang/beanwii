module ui.reng.wiidebugger;

version (linux) {
    import re;
    import re.gfx;
    import re.math;
    import re.ecs;
    import re.ng.diag;
    import re.util.interop;

    import raylib;
    import raylib_nuklear;
    import nuklear_ext;

    import std.array;
    import std.conv;
    import std.string;

    import ui.reng.wiivideo;
    import ui.reng.nuklear_style;

    enum UI_FS = 16; // font size

    class WiiDebuggerUIRoot : Component, Renderable2D, Updatable {
        mixin Reflect;

        WiiVideo wii_video_display;

        @property public Rectangle bounds() {
            return Rectangle(transform.position2.x, transform.position2.y,
                entity.scene.resolution.x, entity.scene.resolution.y);
        }

        nk_context* ctx;
        nk_colorf bg;

        override void setup() {
            wii_video_display = entity.scene.get_entity("wii_display").get_component!WiiVideo();

            bg = ColorToNuklearF(Colors.RAYWHITE);
            auto ui_font = raylib.LoadFontEx("./res/SourceSansPro-Regular.ttf", UI_FS, null, 0);
            ctx = InitNuklearEx(ui_font, UI_FS);
            SetNuklearScaling(ctx, cast(int) Core.window.scale_dpi);
            apply_style(ctx);

            // nk_color[nk_style_colors.NK_COLOR_COUNT] table;
            // table[nk_style_colors.NK_COLOR_TEXT] = nk_rgba(190, 190, 190, 255);
            // table[nk_style_colors.NK_COLOR_WINDOW] = nk_rgba(30, 33, 40, 215);
            // table[nk_style_colors.NK_COLOR_HEADER] = nk_rgba(181, 45, 69, 220);
            // table[nk_style_colors.NK_COLOR_BORDER] = nk_rgba(51, 55, 67, 255);
            // table[nk_style_colors.NK_COLOR_BUTTON] = nk_rgba(181, 45, 69, 255);
            // table[nk_style_colors.NK_COLOR_BUTTON_HOVER] = nk_rgba(190, 50, 70, 255);
            // table[nk_style_colors.NK_COLOR_BUTTON_ACTIVE] = nk_rgba(195, 55, 75, 255);
            // table[nk_style_colors.NK_COLOR_TOGGLE] = nk_rgba(51, 55, 67, 255);
            // table[nk_style_colors.NK_COLOR_TOGGLE_HOVER] = nk_rgba(45, 60, 60, 255);
            // table[nk_style_colors.NK_COLOR_TOGGLE_CURSOR] = nk_rgba(181, 45, 69, 255);
            // table[nk_style_colors.NK_COLOR_SELECT] = nk_rgba(51, 55, 67, 255);
            // table[nk_style_colors.NK_COLOR_SELECT_ACTIVE] = nk_rgba(181, 45, 69, 255);
            // table[nk_style_colors.NK_COLOR_SLIDER] = nk_rgba(51, 55, 67, 255);
            // table[nk_style_colors.NK_COLOR_SLIDER_CURSOR] = nk_rgba(181, 45, 69, 255);
            // table[nk_style_colors.NK_COLOR_SLIDER_CURSOR_HOVER] = nk_rgba(186, 50, 74, 255);
            // table[nk_style_colors.NK_COLOR_SLIDER_CURSOR_ACTIVE] = nk_rgba(191, 55, 79, 255);
            // table[nk_style_colors.NK_COLOR_PROPERTY] = nk_rgba(51, 55, 67, 255);
            // table[nk_style_colors.NK_COLOR_EDIT] = nk_rgba(51, 55, 67, 225);
            // table[nk_style_colors.NK_COLOR_EDIT_CURSOR] = nk_rgba(190, 190, 190, 255);
            // table[nk_style_colors.NK_COLOR_COMBO] = nk_rgba(51, 55, 67, 255);
            // table[nk_style_colors.NK_COLOR_CHART] = nk_rgba(51, 55, 67, 255);
            // table[nk_style_colors.NK_COLOR_CHART_COLOR] = nk_rgba(170, 40, 60, 255);
            // table[nk_style_colors.NK_COLOR_CHART_COLOR_HIGHLIGHT] = nk_rgba(255, 0, 0, 255);
            // table[nk_style_colors.NK_COLOR_SCROLLBAR] = nk_rgba(30, 33, 40, 255);
            // table[nk_style_colors.NK_COLOR_SCROLLBAR_CURSOR] = nk_rgba(64, 84, 95, 255);
            // table[nk_style_colors.NK_COLOR_SCROLLBAR_CURSOR_HOVER] = nk_rgba(70, 90, 100, 255);
            // table[nk_style_colors.NK_COLOR_SCROLLBAR_CURSOR_ACTIVE] = nk_rgba(75, 95, 105, 255);
            // table[nk_style_colors.NK_COLOR_TAB_HEADER] = nk_rgba(181, 45, 69, 220);
            // nk_style_from_table(ctx, cast(nk_color*) table);

            status("ready.");
        }

        @property string status(string val) {
            // log status
            Core.log.info(format("status: %s", val));
            return status_text = val;
        }

        enum Panel1Tab {
            Tab1,
            Tab2,
            Tab3,
        }

        private string status_text = "";
        Rectangle panel1_bounds;
        Rectangle panel2_bounds;
        Rectangle panel3_bounds;
        Panel1Tab panel1_tab = Panel1Tab.Tab1;

        void update() {
            // keyboard shortcuts
            if (Input.is_key_down(Keys.KEY_LEFT_CONTROL) && Input.is_key_pressed(Keys.KEY_TAB)) {
                // advance tab
                import std.traits : EnumMembers;

                auto panel1_tabs = EnumMembers!Panel1Tab;
                panel1_tab = ((panel1_tab.to!int + 1) % panel1_tabs.length).to!Panel1Tab;
            }
        }

        void render() {
            auto wii_disp_bounds = wii_video_display.bounds;
            // region 1 is to the right of the video display
            auto region1_bounds = Rectangle(wii_disp_bounds.x + wii_disp_bounds.width, wii_disp_bounds.y,
                bounds.width - wii_disp_bounds.width, bounds.height);
            // regiom 2 is below the video display, but not overlapping the panel 1
            auto region2_bounds = Rectangle(wii_disp_bounds.x, wii_disp_bounds.y + wii_disp_bounds.height,
                bounds.width, bounds.height - wii_disp_bounds.height);

            // panel 1 is right below the video display on the left
            panel1_bounds = Rectangle(wii_disp_bounds.x, wii_disp_bounds.y + wii_disp_bounds.height,
                wii_disp_bounds.width, bounds.height - wii_disp_bounds.height);

            // panel 3 is smaller width and 100% tall, docked to the right
            const panel3_right_dock_width = cast(int)(region1_bounds.width * 0.3);
            panel3_bounds = Rectangle(region1_bounds.x + region1_bounds.width - panel3_right_dock_width, region1_bounds.y,
                panel3_right_dock_width, region1_bounds.height);

            // panel 2 is to the right of the video display, and fairly wide, to the left of panel 3
            panel2_bounds = Rectangle(region1_bounds.x, region1_bounds.y,
                region1_bounds.width - panel3_bounds.width, region1_bounds.height);

            UpdateNuklear(ctx);

            // nk_layout_row_begin(ctx, nk_layout_format.NK_STATIC, 30, 2);
            // if (nk_tab(ctx, Panel1Tab.Tab1.to!string.c_str, panel1_tab == Panel1Tab.Tab1)) {
            //     panel1_tab = Panel1Tab.Tab1;
            // }
            // if (nk_tab(ctx, Panel1Tab.Tab2.to!string.c_str, panel1_tab == Panel1Tab.Tab2)) {
            //     panel1_tab = Panel1Tab.Tab2;
            // }

            auto GEN_NK_TABS(TTabs)(string tab_var) {
                import std.traits;
                import std.array : appender;

                auto enum_name = __traits(identifier, TTabs);
                auto tab_names = EnumMembers!TTabs;
                auto num_tabs = tab_names.length;

                auto sb = appender!string;

                sb ~= format("nk_layout_row_begin(ctx, nk_layout_format.NK_STATIC, 30, %d);", num_tabs);

                foreach (i, tab_name; tab_names) {
                    sb ~= format("if (nk_tab(ctx, \"%s\", %s == %s.%s)) { %s = %s.%s; }",
                        tab_name, tab_var, enum_name, tab_name, tab_var, enum_name, tab_name);
                }

                return sb.data;
            }

            // - GUI

            if (nk_begin(ctx, "panel 1", RectangleToNuklear(ctx, panel1_bounds),
                    nk_panel_flags.NK_WINDOW_BORDER | nk_panel_flags.NK_WINDOW_TITLE)) {
                nk_layout_row_dynamic(ctx, 30, 1);
                // have a button and some rows
                if (nk_button_label(ctx, "button"))
                    TraceLog(TraceLogLevel.LOG_INFO, "button pressed");
                nk_layout_row_dynamic(ctx, 30, 2);
                // have some labels and some rows
                nk_label(ctx, "first label", nk_text_alignment.NK_TEXT_LEFT);
                nk_label(ctx, "second label", nk_text_alignment.NK_TEXT_LEFT);
            }

            nk_end(ctx);

            if (nk_begin(ctx, "panel 2", RectangleToNuklear(ctx, panel2_bounds),
                    nk_panel_flags.NK_WINDOW_BORDER)) {

                // menu bar
                nk_menubar_begin(ctx);
                nk_layout_row_begin(ctx, nk_layout_format.NK_STATIC, 25, 2);
                nk_layout_row_push(ctx, 45);
                if (nk_menu_begin_label(ctx, "File", nk_text_alignment.NK_TEXT_LEFT, nk_vec2_(120, 200))) {
                    nk_layout_row_dynamic(ctx, 25, 1);
                    if (nk_menu_item_label(ctx, "Open", nk_text_alignment.NK_TEXT_LEFT))
                        TraceLog(TraceLogLevel.LOG_INFO, "Open");
                    if (nk_menu_item_label(ctx, "Close", nk_text_alignment.NK_TEXT_LEFT))
                        TraceLog(TraceLogLevel.LOG_INFO, "Close");
                    nk_menu_end(ctx);
                }
                nk_layout_row_push(ctx, 45);
                if (nk_menu_begin_label(ctx, "Edit", nk_text_alignment.NK_TEXT_LEFT, nk_vec2_(120, 200))) {
                    nk_layout_row_dynamic(ctx, 25, 1);
                    if (nk_menu_item_label(ctx, "Copy", nk_text_alignment.NK_TEXT_LEFT))
                        TraceLog(TraceLogLevel.LOG_INFO, "Copy");
                    if (nk_menu_item_label(ctx, "Paste", nk_text_alignment.NK_TEXT_LEFT))
                        TraceLog(TraceLogLevel.LOG_INFO, "Paste");
                    nk_menu_end(ctx);
                }
                nk_menubar_end(ctx);
                nk_layout_row_dynamic(ctx, UI_PAD, 1);

                enum Difficulty {
                    Easy,
                    Hard,
                }

                static auto diff_opt = Difficulty.Easy;
                static auto property = 20;

                mixin(GEN_NK_TABS!(Panel1Tab)("panel1_tab"));

                auto curr_win_space = nk_window_get_content_region_size(ctx);
                nk_layout_row_dynamic(ctx, curr_win_space.y - 42, 1);

                if (nk_group_begin(ctx, "dashboard", nk_panel_flags.NK_WINDOW_BORDER)) {
                    nk_layout_row_dynamic(ctx, UI_PAD, 1);
                    switch (panel1_tab) {
                    case Panel1Tab.Tab1:
                        nk_layout_row_static(ctx, 30, 80, 1);
                        if (nk_button_label(ctx, "button"))
                            TraceLog(TraceLogLevel.LOG_INFO, "button pressed");

                        nk_layout_row_dynamic(ctx, 30, 2);
                        if (nk_option_label(ctx, "easy", diff_opt == Difficulty.Easy))
                            diff_opt = Difficulty.Easy;
                        if (nk_option_label(ctx, "hard", diff_opt == Difficulty.Hard))
                            diff_opt = Difficulty.Hard;
                        break;
                    case Panel1Tab.Tab2:
                        nk_layout_row_dynamic(ctx, 25, 1);
                        nk_property_int(ctx, "Compression:", 0, &property, 100, 10, 1);

                        nk_layout_row_dynamic(ctx, 20, 1);
                        nk_label(ctx, "background:", nk_text_alignment.NK_TEXT_LEFT);
                        nk_layout_row_dynamic(ctx, 25, 1);
                        if (nk_combo_begin_color(ctx, nk_rgb_cf(bg), nk_vec2(nk_widget_width(ctx), 400))) {
                            nk_layout_row_dynamic(ctx, 120, 1);
                            bg = nk_color_picker(ctx, bg, nk_color_format.NK_RGBA);
                            nk_layout_row_dynamic(ctx, 25, 1);
                            bg.r = nk_propertyf(ctx, "#R:", 0, bg.r, 1.0f, 0.01f, 0.005f);
                            bg.g = nk_propertyf(ctx, "#G:", 0, bg.g, 1.0f, 0.01f, 0.005f);
                            bg.b = nk_propertyf(ctx, "#B:", 0, bg.b, 1.0f, 0.01f, 0.005f);
                            bg.a = nk_propertyf(ctx, "#A:", 0, bg.a, 1.0f, 0.01f, 0.005f);
                            nk_combo_end(ctx);
                        }
                        break;
                    case Panel1Tab.Tab3:
                        nk_layout_row_dynamic(ctx, 30, 1);
                        nk_label(ctx, "Tab 3", nk_text_alignment.NK_TEXT_LEFT);
                        break;
                    default:
                        break;
                    }
                    nk_group_end(ctx);
                }
            }

            nk_end(ctx);

            if (nk_begin(ctx, "panel 3", RectangleToNuklear(ctx, panel3_bounds),
                    nk_panel_flags.NK_WINDOW_BORDER | nk_panel_flags.NK_WINDOW_TITLE)) {
                nk_layout_row_dynamic(ctx, UI_PAD, 1);
                // // have a button and some rows
                // if (nk_button_label(ctx, "button"))
                //     TraceLog(TraceLogLevel.LOG_INFO, "button pressed");
                // nk_layout_row_dynamic(ctx, 30, 2);
                // // have some labels and some rows
                // nk_label(ctx, "first label", nk_text_alignment.NK_TEXT_LEFT);
                // nk_label(ctx, "second label", nk_text_alignment.NK_TEXT_LEFT);

                nk_layout_row_dynamic(ctx, 480, 1);
                nk_list_view list_view;
                if (nk_list_view_begin(ctx, &list_view, "test_list", 0, 12, 1024)) {
                    nk_layout_row_dynamic(ctx, 30, 1);
                    for (int i = 0; i < list_view.count; i++) {
                        auto id = list_view.begin + i;
                        nk_label(ctx, format("item %d", id).c_str, nk_text_alignment.NK_TEXT_LEFT);
                    }
                    nk_list_view_end(&list_view);
                }
            }

            nk_end(ctx);

            DrawNuklear(ctx);
        }

        void debug_render() {
            raylib.DrawRectangleLinesEx(bounds, 1, Colors.RED);
            raylib.DrawRectangleLinesEx(panel1_bounds, 1, Colors.PURPLE);
            raylib.DrawRectangleLinesEx(panel2_bounds, 1, Colors.PURPLE);
            raylib.DrawRectangleLinesEx(panel3_bounds, 1, Colors.PURPLE);
        }
    }
}