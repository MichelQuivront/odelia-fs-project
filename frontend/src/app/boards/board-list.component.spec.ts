import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { signal } from '@angular/core';

import { BoardListComponent } from './board-list.component';
import { routes } from '../app.routes';
import { AuthService } from '../auth/auth.service';

describe('BoardListComponent', () => {
  let http: HttpTestingController;
  /** The signed-in user, swappable per test (stands in for keycloak-js). */
  const auth = { username: signal<string | null>('alice'), isAdmin: signal(false) };

  beforeEach(async () => {
    auth.username.set('alice');
    auth.isAdmin.set(false);
    await TestBed.configureTestingModule({
      imports: [BoardListComponent],
      providers: [
        provideRouter(routes),
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: auth }
      ]
    }).compileComponents();
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  /** Creates the component and answers the initial GET /api/boards. */
  function loaded() {
    const fixture = TestBed.createComponent(BoardListComponent);
    const component = fixture.componentInstance;
    fixture.detectChanges();
    http.expectOne('/api/boards').flush([
      { id: 1, name: 'Zebra', owner: 'alice' },
      { id: 2, name: 'Apple', owner: 'alice' }
    ]);
    fixture.detectChanges();
    return { fixture, component };
  }

  it('loads the initial boards', () => {
    const { component } = loaded();
    expect(component.boards().map(b => b.name)).toEqual(['Zebra', 'Apple']);
    expect(component.loading()).toBeFalse();
  });

  it('PUTs the trimmed name once, replaces the board, re-sorts and closes the editor', () => {
    const { component } = loaded();

    const board = component.boards().find(b => b.id === 1)!;
    component.startRename(board);
    expect(component.editingBoardId()).toBe(1);
    expect(component.renameDraft).toBe('Zebra');

    component.renameDraft = '  Aardvark  ';
    component.saveRename(board);
    component.saveRename(board); // a double submit must not send a second request

    const put = http.expectOne('/api/boards/1');
    expect(put.request.method).toBe('PUT');
    expect(put.request.body).toEqual({ name: 'Aardvark' });
    put.flush({ id: 1, name: 'Aardvark', owner: 'alice' });

    expect(component.boards().map(b => b.name)).toEqual(['Aardvark', 'Apple']);
    expect(component.editingBoardId()).toBeNull();
    expect(component.renaming()).toBeFalse();
  });

  it('Cancel leaves the board unchanged and sends nothing', () => {
    const { component } = loaded();
    const board = component.boards()[0];

    component.startRename(board);
    component.renameDraft = 'Something else';
    component.cancelRename();

    expect(component.editingBoardId()).toBeNull();
    expect(board.name).toBe('Zebra');
    http.expectNone('/api/boards/1');
  });

  it('does not send a blank name and disables Save', () => {
    const { fixture, component } = loaded();
    const board = component.boards()[0];

    component.startRename(board);
    component.renameDraft = '   ';
    fixture.detectChanges();
    component.saveRename(board);

    http.expectNone('/api/boards/1');
    const save: HTMLButtonElement = fixture.nativeElement.querySelector('form.rename button[type=submit]');
    expect(save.disabled).toBeTrue();
  });

  it('opens only one editor at a time', () => {
    const { fixture, component } = loaded();

    component.startRename(component.boards()[0]);
    component.startRename(component.boards()[1]);
    fixture.detectChanges();

    expect(component.editingBoardId()).toBe(2);
    expect(fixture.nativeElement.querySelectorAll('form.rename').length).toBe(1);
  });

  it('keeps the editor and the draft open and shows an error when the rename fails', () => {
    const { component } = loaded();
    const board = component.boards()[0];

    component.startRename(board);
    component.renameDraft = 'Taken';
    component.saveRename(board);
    http.expectOne('/api/boards/1').flush({ error: 'nope' }, { status: 403, statusText: 'Forbidden' });

    expect(component.error()).toBe('Could not rename "Zebra"');
    expect(component.editingBoardId()).toBe(1);
    expect(component.renameDraft).toBe('Taken');
    expect(component.boards().map(b => b.name)).toEqual(['Zebra', 'Apple']);
  });

  // ------------------------------------------------------------ exercise 17

  /** alice owns "Mine"; "Theirs" is bob's board shared with alice. */
  function loadedShared() {
    const fixture = TestBed.createComponent(BoardListComponent);
    fixture.detectChanges();
    http.expectOne('/api/boards').flush([
      { id: 1, name: 'Mine', owner: 'alice' },
      { id: 2, name: 'Theirs', owner: 'bob' }
    ]);
    fixture.detectChanges();
    const rows: HTMLElement[] = Array.from(fixture.nativeElement.querySelectorAll('li.board'));
    const text = (i: number) => rows[i].textContent ?? '';
    return { fixture, rows, text };
  }

  it('F1 - lists shared boards and marks them as shared', () => {
    const { rows, text } = loadedShared();
    expect(rows.length).toBe(2);
    expect(text(0)).not.toContain('shared with you');
    expect(text(1)).toContain('shared with you');
  });

  it('F5 - hides Delete (and Rename) from a member, shows them to the owner', () => {
    const { text } = loadedShared();
    expect(text(0)).toContain('Delete');
    expect(text(0)).toContain('Rename');
    expect(text(1)).not.toContain('Delete');
    expect(text(1)).not.toContain('Rename');
  });

  it('F5 - an admin keeps Delete and Rename on boards they do not own', () => {
    auth.username.set('carol');
    auth.isAdmin.set(true);
    const { text } = loadedShared();
    expect(text(0)).toContain('Delete');
    expect(text(1)).toContain('Delete');
    expect(text(1)).toContain('Rename');
  });
});
