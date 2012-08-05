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

#include "gd-main-toolbar.h"

#include <math.h>
#include <glib/gi18n.h>

G_DEFINE_TYPE (GdMainToolbar, gd_main_toolbar, GTK_TYPE_TOOLBAR)

typedef enum {
  CHILD_NORMAL = 0,
  CHILD_TOGGLE = 1,
  CHILD_MENU = 2,
} ChildType;

struct _GdMainToolbarPrivate {
  GtkSizeGroup *size_group;
  GtkSizeGroup *vertical_size_group;

  GtkToolItem *left_group;
  GtkToolItem *center_group;
  GtkToolItem *right_group;

  GtkWidget *left_grid;

  GtkWidget *title_label;
  GtkWidget *detail_label;

  GtkWidget *right_grid;
};

static void
gd_main_toolbar_dispose (GObject *obj)
{
  GdMainToolbar *self = GD_MAIN_TOOLBAR (obj);

  g_clear_object (&self->priv->size_group);
  g_clear_object (&self->priv->vertical_size_group);

  G_OBJECT_CLASS (gd_main_toolbar_parent_class)->dispose (obj);
}

static gint
get_icon_margin (void)
{
  gint toolbar_size, menu_size;

  gtk_icon_size_lookup (GTK_ICON_SIZE_MENU, &menu_size, NULL);
  gtk_icon_size_lookup (GTK_ICON_SIZE_LARGE_TOOLBAR, &toolbar_size, NULL);
  return (gint) floor ((toolbar_size - menu_size) / 2.0);
}

static GtkSizeGroup *
get_vertical_size_group (void)
{
  GtkSizeGroup *retval;
  GtkWidget *w, *dummy;
  gint icon_margin;

  icon_margin = get_icon_margin ();

  dummy = gtk_toggle_button_new ();
  w = gtk_image_new_from_stock (GTK_STOCK_OPEN, GTK_ICON_SIZE_MENU);
  g_object_set (w, "margin", icon_margin, NULL);
  gtk_container_add (GTK_CONTAINER (dummy), w);
  gtk_widget_show_all (dummy);

  retval = gtk_size_group_new (GTK_SIZE_GROUP_VERTICAL);
  gtk_size_group_add_widget (retval, dummy);

  return retval;
}

static GtkWidget *
get_empty_button (ChildType type)
{
  GtkWidget *button;

  switch (type)
    {
    case CHILD_MENU:
      button = gtk_menu_button_new ();
      break;
    case CHILD_TOGGLE:
      button = gtk_toggle_button_new ();
      break;
    case CHILD_NORMAL:
    default:
      button = gtk_button_new ();
      break;
    }

  return button;
}

static GtkWidget *
get_symbolic_button (const gchar *icon_name,
                     ChildType    type)
{
  GtkWidget *button, *w;

  switch (type)
    {
    case CHILD_MENU:
      button = gtk_menu_button_new ();
      gtk_widget_destroy (gtk_bin_get_child (GTK_BIN (button)));
      break;
    case CHILD_TOGGLE:
      button = gtk_toggle_button_new ();
      break;
    case CHILD_NORMAL:
    default:
      button = gtk_button_new ();
      break;
    }

  gtk_style_context_add_class (gtk_widget_get_style_context (button), "raised");

  w = gtk_image_new_from_icon_name (icon_name, GTK_ICON_SIZE_MENU);
  g_object_set (w, "margin", get_icon_margin (), NULL);
  gtk_widget_show (w);
  gtk_container_add (GTK_CONTAINER (button), w);

  return button;
}

static GtkWidget *
get_text_button (const gchar *label,
                 ChildType    type)
{
  GtkWidget *button, *w;

  switch (type)
    {
    case CHILD_MENU:
      button = gtk_menu_button_new ();
      gtk_widget_destroy (gtk_bin_get_child (GTK_BIN (button)));

      w = gtk_label_new (label);
      gtk_widget_show (w);
      gtk_container_add (GTK_CONTAINER (button), w);
      break;
    case CHILD_TOGGLE:
      button = gtk_toggle_button_new_with_label (label);
      break;
    case CHILD_NORMAL:
    default:
      button = gtk_button_new_with_label (label);
      break;
    }

  gtk_widget_set_vexpand (button, TRUE);
  gtk_style_context_add_class (gtk_widget_get_style_context (button), "raised");

  return button;
}

static void
gd_main_toolbar_constructed (GObject *obj)
{
  GdMainToolbar *self = GD_MAIN_TOOLBAR (obj);
  GtkToolbar *tb = GTK_TOOLBAR (obj);
  GtkWidget *grid;

  G_OBJECT_CLASS (gd_main_toolbar_parent_class)->constructed (obj);

  self->priv->vertical_size_group = get_vertical_size_group ();

  /* left section */
  self->priv->left_group = gtk_tool_item_new ();
  gtk_widget_set_margin_right (GTK_WIDGET (self->priv->left_group), 12);
  gtk_toolbar_insert (tb, self->priv->left_group, -1);
  gtk_size_group_add_widget (self->priv->vertical_size_group,
                             GTK_WIDGET (self->priv->left_group));

  /* left button group */
  self->priv->left_grid = gtk_grid_new ();
  gtk_grid_set_column_spacing (GTK_GRID (self->priv->left_grid), 12);
  gtk_container_add (GTK_CONTAINER (self->priv->left_group), self->priv->left_grid);

  /* center section */
  self->priv->center_group = gtk_tool_item_new ();
  gtk_tool_item_set_expand (self->priv->center_group, TRUE);
  gtk_toolbar_insert (tb, self->priv->center_group, -1);
  gtk_size_group_add_widget (self->priv->vertical_size_group,
                             GTK_WIDGET (self->priv->center_group));

  /* centered label group */
  grid = gtk_grid_new ();
  gtk_widget_set_halign (grid, GTK_ALIGN_CENTER);
  gtk_widget_set_valign (grid, GTK_ALIGN_CENTER);
  gtk_grid_set_column_spacing (GTK_GRID (grid), 12);
  gtk_container_add (GTK_CONTAINER (self->priv->center_group), grid);

  self->priv->title_label = gtk_label_new (NULL);
  gtk_label_set_ellipsize (GTK_LABEL (self->priv->title_label), PANGO_ELLIPSIZE_END);
  gtk_container_add (GTK_CONTAINER (grid), self->priv->title_label);

  self->priv->detail_label = gtk_label_new (NULL);
  gtk_widget_set_no_show_all (self->priv->detail_label, TRUE);
  gtk_style_context_add_class (gtk_widget_get_style_context (self->priv->detail_label), "dim-label");
  gtk_container_add (GTK_CONTAINER (grid), self->priv->detail_label);

  /* right section */
  self->priv->right_group = gtk_tool_item_new ();
  gtk_widget_set_margin_left (GTK_WIDGET (self->priv->right_group), 12);
  gtk_toolbar_insert (tb, self->priv->right_group, -1);
  gtk_size_group_add_widget (self->priv->vertical_size_group,
                             GTK_WIDGET (self->priv->right_group));

  self->priv->right_grid = gtk_grid_new ();
  gtk_grid_set_column_spacing (GTK_GRID (self->priv->right_grid), 12);
  gtk_container_add (GTK_CONTAINER (self->priv->right_group), self->priv->right_grid);

  self->priv->size_group = gtk_size_group_new (GTK_SIZE_GROUP_HORIZONTAL);
  gtk_size_group_add_widget (self->priv->size_group, GTK_WIDGET (self->priv->left_group));
  gtk_size_group_add_widget (self->priv->size_group, GTK_WIDGET (self->priv->right_group));
}

static void
gd_main_toolbar_init (GdMainToolbar *self)
{
  self->priv = G_TYPE_INSTANCE_GET_PRIVATE (self, GD_TYPE_MAIN_TOOLBAR, GdMainToolbarPrivate);
}

static void
gd_main_toolbar_class_init (GdMainToolbarClass *klass)
{
  GObjectClass *oclass;

  oclass = G_OBJECT_CLASS (klass);
  oclass->constructed = gd_main_toolbar_constructed;
  oclass->dispose = gd_main_toolbar_dispose;

  g_type_class_add_private (klass, sizeof (GdMainToolbarPrivate));
}

void
gd_main_toolbar_clear (GdMainToolbar *self)
{
  /* reset labels */
  gtk_label_set_text (GTK_LABEL (self->priv->title_label), "");
  gtk_label_set_text (GTK_LABEL (self->priv->detail_label), "");

  /* clear all added buttons */
  gtk_container_foreach (GTK_CONTAINER (self->priv->left_grid),
                         (GtkCallback) gtk_widget_destroy, self);
  gtk_container_foreach (GTK_CONTAINER (self->priv->right_grid), 
                         (GtkCallback) gtk_widget_destroy, self);
}

/**
 * gd_main_toolbar_set_labels:
 * @self:
 * @primary: (allow-none):
 * @detail: (allow-none):
 *
 */
void
gd_main_toolbar_set_labels (GdMainToolbar *self,
                            const gchar *primary,
                            const gchar *detail)
{
  gchar *real_primary = NULL;

  if (primary != NULL)
    real_primary = g_markup_printf_escaped ("<b>%s</b>", primary);

  if (real_primary == NULL)
    {
      gtk_label_set_markup (GTK_LABEL (self->priv->title_label), "");
      gtk_widget_hide (self->priv->title_label);
    }
  else
    {
      gtk_label_set_markup (GTK_LABEL (self->priv->title_label), real_primary);
      gtk_widget_show (self->priv->title_label);
    }

  if (detail == NULL)
    {
      gtk_label_set_text (GTK_LABEL (self->priv->detail_label), "");
      gtk_widget_hide (self->priv->detail_label);
    }
  else
    {
      gtk_label_set_text (GTK_LABEL (self->priv->detail_label), detail);
      gtk_widget_show (self->priv->detail_label);
    }

  g_free (real_primary);
}

GtkWidget *
gd_main_toolbar_new (void)
{
  return g_object_new (GD_TYPE_MAIN_TOOLBAR, NULL);
}

static GtkWidget *
add_button_internal (GdMainToolbar *self,
                     const gchar *icon_name,
                     const gchar *label,
                     gboolean pack_start,
                     ChildType type)
{
  GtkWidget *button;

  if (icon_name != NULL)
    {
      button = get_symbolic_button (icon_name, type);
      if (label != NULL)
        gtk_widget_set_tooltip_text (button, label);
    }
  else if (label != NULL)
    {
      button = get_text_button (label, type);
    }
  else
    {
      button = get_empty_button (type);
    }

  if (pack_start)
    gtk_container_add (GTK_CONTAINER (self->priv->left_grid), button);
  else
    gtk_container_add (GTK_CONTAINER (self->priv->right_grid), button);    

  gtk_widget_show_all (button);

  return button;
}

/**
 * gd_main_toolbar_add_button:
 * @self:
 * @icon_name: (allow-none):
 * @label: (allow-none):
 * @pack_start:
 *
 * Returns: (transfer none):
 */
GtkWidget *
gd_main_toolbar_add_button (GdMainToolbar *self,
                            const gchar *icon_name,
                            const gchar *label,
                            gboolean pack_start)
{
  return add_button_internal (self, icon_name, label, pack_start, CHILD_NORMAL);
}

/**
 * gd_main_toolbar_add_menu:
 * @self:
 * @icon_name: (allow-none):
 * @label: (allow-none):
 * @pack_start:
 *
 * Returns: (transfer none):
 */
GtkWidget *
gd_main_toolbar_add_menu (GdMainToolbar *self,
                          const gchar *icon_name,
                          const gchar *label,
                          gboolean pack_start)
{
  return add_button_internal (self, icon_name, label, pack_start, CHILD_MENU);
}

/**
 * gd_main_toolbar_add_toggle:
 * @self:
 * @icon_name: (allow-none):
 * @label: (allow-none):
 * @pack_start:
 *
 * Returns: (transfer none):
 */
GtkWidget *
gd_main_toolbar_add_toggle (GdMainToolbar *self,
                            const gchar *icon_name,
                            const gchar *label,
                            gboolean pack_start)
{
  return add_button_internal (self, icon_name, label, pack_start, CHILD_TOGGLE);
}
