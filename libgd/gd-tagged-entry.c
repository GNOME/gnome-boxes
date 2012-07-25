/*
 * Copyright (c) 2011 Red Hat, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by 
 * the Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public 
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License 
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * Author: Cosimo Cecchi <cosimoc@redhat.com>
 *
 */

#include "gd-tagged-entry.h"

#include <math.h>

G_DEFINE_TYPE (GdTaggedEntry, gd_tagged_entry, GTK_TYPE_SEARCH_ENTRY)

#define BUTTON_INTERNAL_SPACING 6

typedef struct {
  GdkWindow *window;
  PangoLayout *layout;

  gchar *id;
  gchar *label;

  GdkPixbuf *close_pixbuf;
  GtkStateFlags last_button_state;
} GdTaggedEntryTag;

struct _GdTaggedEntryPrivate {
  GList *tags;

  GdTaggedEntryTag *in_child;
  gboolean in_child_button;
  gboolean in_child_active;
  gboolean in_child_button_active;
  gboolean button_visible;
};

enum {
  SIGNAL_TAG_CLICKED,
  SIGNAL_TAG_BUTTON_CLICKED,
  LAST_SIGNAL
};

enum {
  PROP_0,
  PROP_TAG_BUTTON_VISIBLE,
  NUM_PROPERTIES
};

static guint signals[LAST_SIGNAL] = { 0, };
static GParamSpec *properties[NUM_PROPERTIES] = { NULL, };

static void gd_tagged_entry_get_text_area_size (GtkEntry *entry,
                                                gint *x,
                                                gint *y,
                                                gint *width,
                                                gint *height);
static gint gd_tagged_entry_tag_get_width (GdTaggedEntryTag *tag,
                                           GdTaggedEntry *entry);
static GtkStyleContext * gd_tagged_entry_tag_get_context (GdTaggedEntry *entry);

static void
gd_tagged_entry_tag_get_margin (GdTaggedEntry *entry,
                                GtkBorder *margin)
{
  GtkStyleContext *context;

  context = gd_tagged_entry_tag_get_context (entry);
  gtk_style_context_get_margin (context, 0, margin);
  g_object_unref (context);
}

static void
gd_tagged_entry_tag_ensure_close_pixbuf (GdTaggedEntryTag *tag,
                                         GtkStyleContext *context)
{
  GtkIconInfo *info;
  gint icon_size;

  if (tag->close_pixbuf != NULL)
    return;

  gtk_icon_size_lookup (GTK_ICON_SIZE_MENU,
                        &icon_size, NULL);

  info = gtk_icon_theme_lookup_icon (gtk_icon_theme_get_default (),
                                     "window-close-symbolic",
                                     icon_size,
                                     GTK_ICON_LOOKUP_GENERIC_FALLBACK);

  tag->close_pixbuf = 
    gtk_icon_info_load_symbolic_for_context (info, context,
                                             NULL, NULL);

  /* FIXME: we need a fallback icon in case the icon is not found */
}

static gint
gd_tagged_entry_tag_panel_get_height (GdTaggedEntry *entry)
{
  GtkWidget *widget = GTK_WIDGET (entry);
  gint height, req_height;
  GtkRequisition requisition;
  GtkAllocation allocation;
  GtkBorder margin;

  gtk_widget_get_allocation (widget, &allocation);
  gtk_widget_get_preferred_size (widget, &requisition, NULL);
  gd_tagged_entry_tag_get_margin (entry, &margin);

  /* the tag panel height is the whole entry height, minus the tag margins */
  req_height = requisition.height - gtk_widget_get_margin_top (widget) - gtk_widget_get_margin_bottom (widget);
  height = MIN (req_height, allocation.height) - margin.top - margin.bottom;

  return height;
}

static void
gd_tagged_entry_tag_panel_get_position (GdTaggedEntry *self,
                                        gint *x_out, 
                                        gint *y_out)
{
  GtkWidget *widget = GTK_WIDGET (self);
  gint text_x, text_y, text_width, text_height, req_height;
  GtkAllocation allocation;
  GtkRequisition requisition;
  GtkBorder margin;

  gtk_widget_get_allocation (widget, &allocation);
  gtk_widget_get_preferred_size (widget, &requisition, NULL);
  req_height = requisition.height - gtk_widget_get_margin_top (widget) - gtk_widget_get_margin_bottom (widget);

  gd_tagged_entry_get_text_area_size (GTK_ENTRY (self), &text_x, &text_y, &text_width, &text_height);
  gd_tagged_entry_tag_get_margin (self, &margin);

  /* allocate the panel immediately after the text area */
  if (x_out)
    *x_out = allocation.x + text_x + text_width;
  if (y_out)
    *y_out = allocation.y + margin.top + (gint) floor ((allocation.height - req_height) / 2);
}

static gint
gd_tagged_entry_tag_panel_get_width (GdTaggedEntry *self)
{
  GdTaggedEntryTag *tag;
  gint width;
  GList *l;

  width = 0;

  for (l = self->priv->tags; l != NULL; l = l->next)
    {
      tag = l->data;
      width += gd_tagged_entry_tag_get_width (tag, self);
    }

  return width;
}

static void
gd_tagged_entry_tag_ensure_layout (GdTaggedEntryTag *tag,
                                   GdTaggedEntry *entry)
{
  if (tag->layout != NULL)
    return;

  tag->layout = pango_layout_new (gtk_widget_get_pango_context (GTK_WIDGET (entry)));
  pango_layout_set_text (tag->layout, tag->label, -1);
}

static GtkStateFlags
gd_tagged_entry_tag_get_state (GdTaggedEntryTag *tag,
                               GdTaggedEntry *entry)
{
  GtkStateFlags state = GTK_STATE_FLAG_NORMAL;

  if (entry->priv->in_child == tag)
    state |= GTK_STATE_FLAG_PRELIGHT;

  if (entry->priv->in_child_active)
    state |= GTK_STATE_FLAG_ACTIVE;

  return state;
}

static GtkStateFlags
gd_tagged_entry_tag_get_button_state (GdTaggedEntryTag *tag,
                                      GdTaggedEntry *entry)
{
  GtkStateFlags state = GTK_STATE_FLAG_NORMAL;

  if (entry->priv->in_child == tag &&
      entry->priv->in_child_button)
    state |= GTK_STATE_FLAG_PRELIGHT;

  if (entry->priv->in_child_button_active)
    state |= GTK_STATE_FLAG_ACTIVE;

  return state;
}

static GtkStyleContext *
gd_tagged_entry_tag_get_context (GdTaggedEntry *entry)
{
  GtkWidget *widget = GTK_WIDGET (entry);
  GtkWidgetPath *path;
  gint pos;
  GtkStyleContext *retval;

  retval = gtk_style_context_new ();
  path = gtk_widget_path_copy (gtk_widget_get_path (widget));

  pos = gtk_widget_path_append_type (path, GD_TYPE_TAGGED_ENTRY);
  gtk_widget_path_iter_add_class (path, pos, "documents-entry-tag");

  gtk_style_context_set_path (retval, path);

  gtk_widget_path_unref (path);

  return retval;
}

static gint
gd_tagged_entry_tag_get_width (GdTaggedEntryTag *tag,
                               GdTaggedEntry *entry)
{
  GtkBorder button_padding, button_border, button_margin;
  GtkStyleContext *context;
  GtkStateFlags state;
  gint layout_width;
  gint button_width;

  gd_tagged_entry_tag_ensure_layout (tag, entry);
  pango_layout_get_pixel_size (tag->layout, &layout_width, NULL);

  context = gd_tagged_entry_tag_get_context (entry);
  state = gd_tagged_entry_tag_get_state (tag, entry);

  gtk_style_context_get_padding (context, state, &button_padding);
  gtk_style_context_get_border (context, state, &button_border);
  gtk_style_context_get_margin (context, state, &button_margin);

  gd_tagged_entry_tag_ensure_close_pixbuf (tag, context);

  g_object_unref (context);

  button_width = 0;
  if (entry->priv->button_visible)
    button_width = gdk_pixbuf_get_width (tag->close_pixbuf) + BUTTON_INTERNAL_SPACING;

  return layout_width + button_padding.left + button_padding.right +
    button_border.left + button_border.right +
    button_margin.left + button_margin.right +
    button_width;
}

static void
gd_tagged_entry_tag_get_size (GdTaggedEntryTag *tag,
                              GdTaggedEntry *entry,
                              gint *width_out,
                              gint *height_out)
{
  gint width, panel_height;

  width = gd_tagged_entry_tag_get_width (tag, entry);
  panel_height = gd_tagged_entry_tag_panel_get_height (entry);

  if (width_out)
    *width_out = width;
  if (height_out)
    *height_out = panel_height;
}

static void
gd_tagged_entry_tag_get_relative_allocations (GdTaggedEntryTag *tag,
                                              GdTaggedEntry *entry,
                                              GtkStyleContext *context,
                                              GtkAllocation *background_allocation_out,
                                              GtkAllocation *layout_allocation_out,
                                              GtkAllocation *button_allocation_out)
{
  GtkAllocation background_allocation, layout_allocation, button_allocation;
  gint width, height, x, y, pix_width, pix_height;
  gint layout_width, layout_height;
  GtkBorder padding, border;
  GtkStateFlags state;

  width = gdk_window_get_width (tag->window);
  height = gdk_window_get_height (tag->window);

  state = gd_tagged_entry_tag_get_state (tag, entry);
  gtk_style_context_get_margin (context, state, &padding);

  width -= padding.left + padding.right;
  height -= padding.top + padding.bottom;
  x = padding.left;
  y = padding.top;

  background_allocation.x = x;
  background_allocation.y = y;
  background_allocation.width = width;
  background_allocation.height = height;

  layout_allocation = button_allocation = background_allocation;

  gtk_style_context_get_padding (context, state, &padding);
  gtk_style_context_get_border (context, state, &border);  

  gd_tagged_entry_tag_ensure_layout (tag, entry);
  pango_layout_get_pixel_size (tag->layout, &layout_width, &layout_height);

  layout_allocation.x += border.left + padding.left;
  layout_allocation.y += (layout_allocation.height - layout_height) / 2;

  if (entry->priv->button_visible)
    {
      pix_width = gdk_pixbuf_get_width (tag->close_pixbuf);
      pix_height = gdk_pixbuf_get_height (tag->close_pixbuf);
    }
  else
    {
      pix_width = 0;
      pix_height = 0;
    }

  button_allocation.x += width - pix_width - border.right - padding.right;
  button_allocation.y += (height - pix_height) / 2;
  button_allocation.width = pix_width;
  button_allocation.height = pix_height;

  if (background_allocation_out)
    *background_allocation_out = background_allocation;
  if (layout_allocation_out)
    *layout_allocation_out = layout_allocation;
  if (button_allocation_out)
    *button_allocation_out = button_allocation;
}

static gboolean
gd_tagged_entry_tag_event_is_button (GdTaggedEntryTag *tag,
                                     GdTaggedEntry *entry,
                                     gdouble event_x,
                                     gdouble event_y)
{
  GtkAllocation button_allocation;
  GtkStyleContext *context;

  if (!entry->priv->button_visible)
    return FALSE;

  context = gd_tagged_entry_tag_get_context (entry);
  gd_tagged_entry_tag_get_relative_allocations (tag, entry, context, NULL, NULL, &button_allocation);

  g_object_unref (context);

  /* see if the event falls into the button allocation */
  if ((event_x >= button_allocation.x && 
       event_x <= button_allocation.x + button_allocation.width) &&
      (event_y >= button_allocation.y &&
       event_y <= button_allocation.y + button_allocation.height))
    return TRUE;

  return FALSE;
}

static void
gd_tagged_entry_tag_draw (GdTaggedEntryTag *tag,
                          cairo_t *cr,
                          GdTaggedEntry *entry)
{
  GtkStyleContext *context;
  GtkStateFlags state;
  GtkAllocation background_allocation, layout_allocation, button_allocation;

  context = gd_tagged_entry_tag_get_context (entry);
  gd_tagged_entry_tag_get_relative_allocations (tag, entry, context,
                                                &background_allocation,
                                                &layout_allocation,
                                                &button_allocation);

  cairo_save (cr);
  gtk_cairo_transform_to_window (cr, GTK_WIDGET (entry), tag->window);

  gtk_style_context_save (context);

  state = gd_tagged_entry_tag_get_state (tag, entry);
  gtk_style_context_set_state (context, state);
  gtk_render_background (context, cr,
                         background_allocation.x, background_allocation.y,
                         background_allocation.width, background_allocation.height); 
  gtk_render_frame (context, cr,
                    background_allocation.x, background_allocation.y,
                    background_allocation.width, background_allocation.height); 

  gtk_render_layout (context, cr,
                     layout_allocation.x, layout_allocation.y,
                     tag->layout);

  gtk_style_context_restore (context);

  if (!entry->priv->button_visible)
    goto done;

  gtk_style_context_add_class (context, GTK_STYLE_CLASS_BUTTON);
  state = gd_tagged_entry_tag_get_button_state (tag, entry);
  gtk_style_context_set_state (context, state);

  /* if the state changed since last time we draw the pixbuf,
   * clear and redraw it.
   */
  if (state != tag->last_button_state)
    {
      g_clear_object (&tag->close_pixbuf);
      gd_tagged_entry_tag_ensure_close_pixbuf (tag, context);

      tag->last_button_state = state;
    }

  gtk_render_background (context, cr,
                         button_allocation.x, button_allocation.y,
                         button_allocation.width, button_allocation.height);
  gtk_render_frame (context, cr,
                         button_allocation.x, button_allocation.y,
                         button_allocation.width, button_allocation.height);

  gtk_render_icon (context, cr,
                   tag->close_pixbuf,
                   button_allocation.x, button_allocation.y);

done:
  cairo_restore (cr);

  g_object_unref (context);
}

static void
gd_tagged_entry_tag_unrealize (GdTaggedEntryTag *tag)
{
  if (tag->window == NULL)
    return;

  gdk_window_set_user_data (tag->window, NULL);
  gdk_window_destroy (tag->window);
  tag->window = NULL;
}

static void
gd_tagged_entry_tag_realize (GdTaggedEntryTag *tag,
                             GdTaggedEntry *entry)
{
  GtkWidget *widget = GTK_WIDGET (entry);
  GdkWindowAttr attributes;
  gint attributes_mask;
  gint tag_width, tag_height;

  if (tag->window != NULL)
    return;

  attributes.window_type = GDK_WINDOW_CHILD;
  attributes.wclass = GDK_INPUT_ONLY;
  attributes.event_mask = gtk_widget_get_events (widget);
  attributes.event_mask |= GDK_BUTTON_PRESS_MASK
    | GDK_BUTTON_RELEASE_MASK | GDK_LEAVE_NOTIFY_MASK | GDK_ENTER_NOTIFY_MASK
    | GDK_POINTER_MOTION_MASK | GDK_POINTER_MOTION_HINT_MASK;

  gd_tagged_entry_tag_get_size (tag, entry, &tag_width, &tag_height);
  attributes.x = 0;
  attributes.y = 0;
  attributes.width = tag_width;
  attributes.height = tag_height;

  attributes_mask = GDK_WA_X | GDK_WA_Y;

  tag->window = gdk_window_new (gtk_widget_get_window (widget),
                                &attributes, attributes_mask);
  gdk_window_set_user_data (tag->window, widget);
}

static GdTaggedEntryTag *
gd_tagged_entry_tag_new (const gchar *id,
                         const gchar *label)
{
  GdTaggedEntryTag *tag;

  tag = g_slice_new0 (GdTaggedEntryTag);

  tag->id = g_strdup (id);
  tag->label = g_strdup (label);
  tag->last_button_state = GTK_STATE_FLAG_NORMAL;

  return tag;
}

static void
gd_tagged_entry_tag_free (gpointer _tag)
{
  GdTaggedEntryTag *tag = _tag;

  if (tag->window != NULL)
    gd_tagged_entry_tag_unrealize (tag);

  g_clear_object (&tag->layout);
  g_clear_object (&tag->close_pixbuf);
  g_free (tag->id);
  g_free (tag->label);

  g_slice_free (GdTaggedEntryTag, tag);
}

static gboolean
gd_tagged_entry_draw (GtkWidget *widget,
                      cairo_t *cr)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;
  GList *l;

  GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->draw (widget, cr);

  for (l = self->priv->tags; l != NULL; l = l->next)
    {
      tag = l->data;
      gd_tagged_entry_tag_draw (tag, cr, self);
    }

  return FALSE;
}

static void
gd_tagged_entry_map (GtkWidget *widget)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;
  GList *l;

  if (gtk_widget_get_realized (widget) && !gtk_widget_get_mapped (widget))
    {
      GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->map (widget);

      for (l = self->priv->tags; l != NULL; l = l->next)
        {
          tag = l->data;
          gdk_window_show (tag->window);
        }
    }
}

static void
gd_tagged_entry_unmap (GtkWidget *widget)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;
  GList *l;

  if (gtk_widget_get_mapped (widget))
    {
      for (l = self->priv->tags; l != NULL; l = l->next)
        {
          tag = l->data;
          gdk_window_hide (tag->window);
        }

      GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->unmap (widget);
    }
}

static void
gd_tagged_entry_realize (GtkWidget *widget)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;
  GList *l;

  GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->realize (widget);

  for (l = self->priv->tags; l != NULL; l = l->next)
    {
      tag = l->data;
      gd_tagged_entry_tag_realize (tag, self);
    }
}

static void
gd_tagged_entry_unrealize (GtkWidget *widget)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;
  GList *l;

  GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->unrealize (widget);

  for (l = self->priv->tags; l != NULL; l = l->next)
    {
      tag = l->data;
      gd_tagged_entry_tag_unrealize (tag);
    }
}

static void
gd_tagged_entry_get_text_area_size (GtkEntry *entry,
                                    gint *x,
                                    gint *y,
                                    gint *width,
                                    gint *height)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (entry);
  gint tag_panel_width;

  GTK_ENTRY_CLASS (gd_tagged_entry_parent_class)->get_text_area_size (entry, x, y, width, height);

  tag_panel_width = gd_tagged_entry_tag_panel_get_width (self);

  if (width)
    *width -= tag_panel_width;
}

static void
gd_tagged_entry_size_allocate (GtkWidget *widget,
                               GtkAllocation *allocation)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  gint x, y, width, height;
  GdTaggedEntryTag *tag;
  GList *l;

  gtk_widget_set_allocation (widget, allocation);
  GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->size_allocate (widget, allocation);

  if (gtk_widget_get_realized (widget))
    {
      gd_tagged_entry_tag_panel_get_position (self, &x, &y);

      for (l = self->priv->tags; l != NULL; l = l->next)
        {
          tag = l->data;
          gd_tagged_entry_tag_get_size (tag, self, &width, &height);
          gdk_window_move_resize (tag->window, x, y, width, height);

          x += width;
        }

      gtk_widget_queue_draw (widget);
    }
}

static void
gd_tagged_entry_get_preferred_width (GtkWidget *widget,
                                     gint *minimum,
                                     gint *natural)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  gint tag_panel_width;

  GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->get_preferred_width (widget, minimum, natural);

  tag_panel_width = gd_tagged_entry_tag_panel_get_width (self);

  if (minimum)
    *minimum += tag_panel_width;
  if (natural)
    *natural += tag_panel_width;
}

static void
gd_tagged_entry_finalize (GObject *obj)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (obj);

  if (self->priv->tags != NULL)
    {
      g_list_free_full (self->priv->tags, gd_tagged_entry_tag_free);
      self->priv->tags = NULL;
    }

  G_OBJECT_CLASS (gd_tagged_entry_parent_class)->finalize (obj);
}

static GdTaggedEntryTag *
gd_tagged_entry_find_tag_by_id (GdTaggedEntry *self,
                                const gchar *id)
{
  GdTaggedEntryTag *tag = NULL, *elem;
  GList *l;

  for (l = self->priv->tags; l != NULL; l = l->next)
    {
      elem = l->data;
      if (g_strcmp0 (elem->id, id) == 0)
        {
          tag = elem;
          break;
        }
    }

  return tag;
}

static GdTaggedEntryTag *
gd_tagged_entry_find_tag_by_window (GdTaggedEntry *self,
                                    GdkWindow *window)
{
  GdTaggedEntryTag *tag = NULL, *elem;
  GList *l;

  for (l = self->priv->tags; l != NULL; l = l->next)
    {
      elem = l->data;
      if (elem->window == window)
        {
          tag = elem;
          break;
        }
    }

  return tag;
}

static gint
gd_tagged_entry_enter_notify (GtkWidget        *widget,
                              GdkEventCrossing *event)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;

  tag = gd_tagged_entry_find_tag_by_window (self, event->window);

  if (tag != NULL)
    {
      self->priv->in_child = tag;
      gtk_widget_queue_draw (widget);
    }

  return GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->enter_notify_event (widget, event);
}

static gint
gd_tagged_entry_leave_notify (GtkWidget        *widget,
                              GdkEventCrossing *event)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);

  if (self->priv->in_child != NULL)
    {
      self->priv->in_child = NULL;
      gtk_widget_queue_draw (widget);
    }

  return GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->leave_notify_event (widget, event);
}

static gint
gd_tagged_entry_motion_notify (GtkWidget      *widget,
                               GdkEventMotion *event)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;

  tag = gd_tagged_entry_find_tag_by_window (self, event->window);

  if (tag != NULL)
    {
      gdk_event_request_motions (event);

      self->priv->in_child = tag;
      self->priv->in_child_button = gd_tagged_entry_tag_event_is_button (tag, self, event->x, event->y);
      gtk_widget_queue_draw (widget);

      return FALSE;
    }

  return GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->motion_notify_event (widget, event);
}

static gboolean
gd_tagged_entry_button_release_event (GtkWidget *widget,
                                      GdkEventButton *event)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;
  GQuark id_quark;

  tag = gd_tagged_entry_find_tag_by_window (self, event->window);

  if (tag != NULL)
    {
      id_quark = g_quark_from_string (tag->id);
      self->priv->in_child_active = FALSE;

      if (gd_tagged_entry_tag_event_is_button (tag, self, event->x, event->y))
        {
          self->priv->in_child_button_active = FALSE;
          g_signal_emit (self, signals[SIGNAL_TAG_BUTTON_CLICKED], id_quark, tag->id);
        }
      else
        {
          g_signal_emit (self, signals[SIGNAL_TAG_CLICKED], id_quark, tag->id);
        }

      gtk_widget_queue_draw (widget);

      return TRUE;
    }

  return GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->button_release_event (widget, event);
}

static gboolean
gd_tagged_entry_button_press_event (GtkWidget *widget,
                                    GdkEventButton *event)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (widget);
  GdTaggedEntryTag *tag;

  tag = gd_tagged_entry_find_tag_by_window (self, event->window);

  if (tag != NULL)
    {
      if (gd_tagged_entry_tag_event_is_button (tag, self, event->x, event->y))
        self->priv->in_child_button_active = TRUE;
      else
        self->priv->in_child_active = TRUE;

      gtk_widget_queue_draw (widget);

      return TRUE;
    }

  return GTK_WIDGET_CLASS (gd_tagged_entry_parent_class)->button_press_event (widget, event);
}

static void
gd_tagged_entry_init (GdTaggedEntry *self)
{
  self->priv = G_TYPE_INSTANCE_GET_PRIVATE (self, GD_TYPE_TAGGED_ENTRY, GdTaggedEntryPrivate);
  self->priv->button_visible = TRUE;
}

static void
gd_tagged_entry_get_property (GObject      *object,
                              guint         property_id,
                              GValue       *value,
                              GParamSpec   *pspec)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (object);

  switch (property_id)
    {
      case PROP_TAG_BUTTON_VISIBLE:
        g_value_set_boolean (value, gd_tagged_entry_get_tag_button_visible (self));
        break;
      default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
    }
}

static void
gd_tagged_entry_set_property (GObject      *object,
                              guint         property_id,
                              const GValue *value,
                              GParamSpec   *pspec)
{
  GdTaggedEntry *self = GD_TAGGED_ENTRY (object);

  switch (property_id)
    {
      case PROP_TAG_BUTTON_VISIBLE:
        gd_tagged_entry_set_tag_button_visible (self, g_value_get_boolean (value));
        break;
      default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
    }
}

static void
gd_tagged_entry_class_init (GdTaggedEntryClass *klass)
{
  GtkWidgetClass *wclass = GTK_WIDGET_CLASS (klass);
  GtkEntryClass *eclass = GTK_ENTRY_CLASS (klass);
  GObjectClass *oclass = G_OBJECT_CLASS (klass);

  oclass->finalize = gd_tagged_entry_finalize;
  oclass->set_property = gd_tagged_entry_set_property;
  oclass->get_property = gd_tagged_entry_get_property;

  wclass->realize = gd_tagged_entry_realize;
  wclass->unrealize = gd_tagged_entry_unrealize;
  wclass->map = gd_tagged_entry_map;
  wclass->unmap = gd_tagged_entry_unmap;
  wclass->size_allocate = gd_tagged_entry_size_allocate;
  wclass->get_preferred_width = gd_tagged_entry_get_preferred_width;
  wclass->draw = gd_tagged_entry_draw;
  wclass->enter_notify_event = gd_tagged_entry_enter_notify;
  wclass->leave_notify_event = gd_tagged_entry_leave_notify;
  wclass->motion_notify_event = gd_tagged_entry_motion_notify;
  wclass->button_press_event = gd_tagged_entry_button_press_event;
  wclass->button_release_event = gd_tagged_entry_button_release_event;

  eclass->get_text_area_size = gd_tagged_entry_get_text_area_size;

  signals[SIGNAL_TAG_CLICKED] =
    g_signal_new ("tag-clicked",
                  GD_TYPE_TAGGED_ENTRY,
                  G_SIGNAL_RUN_FIRST | G_SIGNAL_DETAILED,
                  0, NULL, NULL, NULL,
                  G_TYPE_NONE,
                  1, G_TYPE_STRING);
  signals[SIGNAL_TAG_BUTTON_CLICKED] =
    g_signal_new ("tag-button-clicked",
                  GD_TYPE_TAGGED_ENTRY,
                  G_SIGNAL_RUN_FIRST | G_SIGNAL_DETAILED,
                  0, NULL, NULL, NULL,
                  G_TYPE_NONE,
                  1, G_TYPE_STRING);

  properties[PROP_TAG_BUTTON_VISIBLE] =
    g_param_spec_boolean ("tag-close-visible", "Tag close icon visibility",
                          "Whether the close button should be shown in tags.", TRUE,
                          G_PARAM_WRITABLE | G_PARAM_STATIC_STRINGS);

  g_type_class_add_private (klass, sizeof (GdTaggedEntryPrivate));
  g_object_class_install_properties (oclass, NUM_PROPERTIES, properties);
}

GdTaggedEntry *
gd_tagged_entry_new (void)
{
  return g_object_new (GD_TYPE_TAGGED_ENTRY, NULL);
}

gboolean
gd_tagged_entry_add_tag (GdTaggedEntry *self,
                         const gchar *id,
                         const gchar *name)
{
  GdTaggedEntryTag *tag;

  if (gd_tagged_entry_find_tag_by_id (self, id) != NULL)
    return FALSE;

  tag = gd_tagged_entry_tag_new (id, name);
  self->priv->tags = g_list_append (self->priv->tags, tag);

  if (gtk_widget_get_mapped (GTK_WIDGET (self)))
    {
      gd_tagged_entry_tag_realize (tag, self);
      gdk_window_show_unraised (tag->window);
    }

  gtk_widget_queue_resize (GTK_WIDGET (self));

  return TRUE;
}

gboolean
gd_tagged_entry_remove_tag (GdTaggedEntry *self,
                            const gchar *id)
{
  GdTaggedEntryTag *tag;
  gboolean res = FALSE;

  tag = gd_tagged_entry_find_tag_by_id (self, id);

  if (tag != NULL)
    {
      res = TRUE;
      self->priv->tags = g_list_remove (self->priv->tags, tag);
      gd_tagged_entry_tag_free (tag);

      gtk_widget_queue_resize (GTK_WIDGET (self));
    }

  return res;
}

gboolean
gd_tagged_entry_set_tag_label (GdTaggedEntry *self,
                               const gchar *tag_id,
                               const gchar *label)
{
  GdTaggedEntryTag *tag;
  gboolean res = FALSE;

  tag = gd_tagged_entry_find_tag_by_id (self, tag_id);

  if (tag != NULL)
    {
      res = TRUE;

      if (g_strcmp0 (tag->label, label) != 0)
        {
          g_free (tag->label);
          tag->label = g_strdup (label);
          g_clear_object (&tag->layout);

          gtk_widget_queue_resize (GTK_WIDGET (self));
        }
    }

  return res;  
}

void
gd_tagged_entry_set_tag_button_visible (GdTaggedEntry *self,
                                        gboolean       visible)
{
  g_return_if_fail (GD_IS_TAGGED_ENTRY (self));

  if (self->priv->button_visible == visible)
    return;

  self->priv->button_visible = visible;
  gtk_widget_queue_resize (GTK_WIDGET (self));

  g_object_notify_by_pspec (G_OBJECT (self), properties[PROP_TAG_BUTTON_VISIBLE]);
}

gboolean
gd_tagged_entry_get_tag_button_visible (GdTaggedEntry *self)
{
  g_return_val_if_fail (GD_IS_TAGGED_ENTRY (self), FALSE);

  return self->priv->button_visible;
}
