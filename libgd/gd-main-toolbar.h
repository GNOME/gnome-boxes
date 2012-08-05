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

#ifndef __GD_MAIN_TOOLBAR_H__
#define __GD_MAIN_TOOLBAR_H__

#include <glib-object.h>

#include <gtk/gtk.h>

G_BEGIN_DECLS

#define GD_TYPE_MAIN_TOOLBAR gd_main_toolbar_get_type()

#define GD_MAIN_TOOLBAR(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST ((obj), \
   GD_TYPE_MAIN_TOOLBAR, GdMainToolbar))

#define GD_MAIN_TOOLBAR_CLASS(klass) \
  (G_TYPE_CHECK_CLASS_CAST ((klass), \
   GD_TYPE_MAIN_TOOLBAR, GdMainToolbarClass))

#define GD_IS_MAIN_TOOLBAR(obj) \
  (G_TYPE_CHECK_INSTANCE_TYPE ((obj), \
   GD_TYPE_MAIN_TOOLBAR))

#define GD_IS_MAIN_TOOLBAR_CLASS(klass) \
  (G_TYPE_CHECK_CLASS_TYPE ((klass), \
   GD_TYPE_MAIN_TOOLBAR))

#define GD_MAIN_TOOLBAR_GET_CLASS(obj) \
  (G_TYPE_INSTANCE_GET_CLASS ((obj), \
   GD_TYPE_MAIN_TOOLBAR, GdMainToolbarClass))

typedef struct _GdMainToolbar GdMainToolbar;
typedef struct _GdMainToolbarClass GdMainToolbarClass;
typedef struct _GdMainToolbarPrivate GdMainToolbarPrivate;

struct _GdMainToolbar
{
  GtkToolbar parent;

  GdMainToolbarPrivate *priv;
};

struct _GdMainToolbarClass
{
  GtkToolbarClass parent_class;
};

GType gd_main_toolbar_get_type (void) G_GNUC_CONST;

GtkWidget     *gd_main_toolbar_new (void);

void        gd_main_toolbar_set_labels (GdMainToolbar *self,
                                        const gchar *primary,
                                        const gchar *detail);

void        gd_main_toolbar_clear (GdMainToolbar *self);

GtkWidget * gd_main_toolbar_add_button (GdMainToolbar *self,
                                        const gchar *icon_name,
                                        const gchar *label,
                                        gboolean pack_start);

GtkWidget * gd_main_toolbar_add_toggle (GdMainToolbar *self,
                                        const gchar *icon_name,
                                        const gchar *label,
                                        gboolean pack_start);

GtkWidget * gd_main_toolbar_add_menu (GdMainToolbar *self,
                                      const gchar *icon_name,
                                      const gchar *label,
                                      gboolean pack_start);

G_END_DECLS

#endif /* __GD_MAIN_TOOLBAR_H__ */
